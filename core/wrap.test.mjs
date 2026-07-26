// rabadon wrap tests — every guarantee proven against fake provider clients.
import test from 'node:test';
import assert from 'node:assert/strict';
import { session, RabadonStop, responseText } from './wrap.mjs';

// --- fake providers ---------------------------------------------------------

/** Fake Anthropic SDK: .messages.create returns scripted responses in order. */
function fakeAnthropic(script) {
  let i = 0;
  return {
    messages: {
      create: async (params) => {
        const r = script[Math.min(i++, script.length - 1)];
        if (r instanceof Error) throw r;
        return typeof r === 'function' ? r(params) : r;
      },
    },
  };
}

const anthropicResp = (text, inTok = 10, outTok = 5) => ({
  content: [{ type: 'text', text }],
  usage: { input_tokens: inTok, output_tokens: outTok },
});

/** Fake OpenAI SDK shape. */
function fakeOpenAI(text) {
  return {
    chat: {
      completions: {
        create: async () => ({
          choices: [{ message: { content: text } }],
          usage: { prompt_tokens: 7, completion_tokens: 3, total_tokens: 10 },
        }),
      },
    },
  };
}

const nonEmpty = (out) => responseText(out).length > 0 || 'empty completion';
nonEmpty.checkName = 'non-empty';

// --- construction laws ------------------------------------------------------

test('session refuses to exist without a bound', () => {
  assert.throws(() => session({}), /unbounded/);
});

test('wrap refuses an unrecognized client', () => {
  const s = session({ maxCalls: 1 });
  assert.throws(() => s.wrap({ not: 'a client' }), /unrecognized client/);
});

// --- guarantee: runaway stops BEFORE the spend ------------------------------

test('maxCalls gates pre-call: the call over the bound never reaches the provider', async () => {
  let providerCalls = 0;
  const client = fakeAnthropic([() => { providerCalls++; return anthropicResp('ok'); }]);
  const s = session({ maxCalls: 2 });
  const wrapped = s.wrap(client);
  await wrapped.messages.create({ model: 'm' });
  await wrapped.messages.create({ model: 'm' });
  await assert.rejects(() => wrapped.messages.create({ model: 'm' }), (err) => {
    assert.ok(err instanceof RabadonStop);
    assert.equal(err.reason, 'RUNAWAY');
    return true;
  });
  assert.equal(providerCalls, 2, 'third call must be refused BEFORE the provider sees it');
});

test('maxTokens counts REAL provider usage and gates the next call', async () => {
  const client = fakeAnthropic([anthropicResp('a', 60, 50)]); // 110 tokens per call
  const s = session({ maxTokens: 100 });
  const wrapped = s.wrap(client);
  await wrapped.messages.create({ model: 'm' }); // spends 110 > 100
  await assert.rejects(() => wrapped.messages.create({ model: 'm' }), /maxTokens=100 spent/);
  assert.equal(s.stats().tokens, 110);
});

// --- guarantee: a broken response does not flow onward ----------------------

test('block mode: failed check throws RabadonStop, response attached for forensics', async () => {
  const s = session({ maxCalls: 5 });
  const wrapped = s.wrap(fakeAnthropic([anthropicResp('')]), { correct: [nonEmpty] });
  await assert.rejects(() => wrapped.messages.create({ model: 'm' }), (err) => {
    assert.ok(err instanceof RabadonStop);
    assert.equal(err.reason, 'CHECK_FAILED');
    assert.equal(err.fails[0].check, 'non-empty');
    assert.ok(err.response, 'the broken response must be attached, not swallowed');
    return true;
  });
  assert.equal(s.stats().blocked, 1);
});

test('observe mode: failed check flows onward but is ON RECORD', async () => {
  const s = session({ maxCalls: 5, mode: 'observe' });
  const wrapped = s.wrap(fakeAnthropic([anthropicResp('')]), { correct: [nonEmpty] });
  const out = await wrapped.messages.create({ model: 'm' });
  assert.equal(responseText(out), '');
  assert.equal(s.stats().observedFails, 1);
});

test('a check with no verdict fails closed', async () => {
  const silent = () => undefined;
  const s = session({ maxCalls: 5 });
  const wrapped = s.wrap(fakeAnthropic([anthropicResp('fine')]), { correct: [silent] });
  await assert.rejects(() => wrapped.messages.create({ model: 'm' }), /no verdict \(fail-closed\)/);
});

// --- the differentiator: bounded repair, re-checked -------------------------

test('repair: broken response is rewritten, re-checked, then flows', async () => {
  const s = session({ maxCalls: 5, maxRepairs: 2 });
  const wrapped = s.wrap(fakeAnthropic([anthropicResp('')]), {
    correct: [nonEmpty],
    repair: async (broken, req, fails) => {
      assert.equal(fails[0].check, 'non-empty');
      return anthropicResp('repaired text', 3, 2);
    },
  });
  const out = await wrapped.messages.create({ model: 'm' });
  assert.equal(responseText(out), 'repaired text');
  assert.equal(s.stats().repaired, 1);
  assert.equal(s.stats().tokens, 15 + 5, 'repair usage counts against the SAME budget');
});

test('repair that never satisfies the checks stops at maxRepairs and blocks', async () => {
  let attempts = 0;
  const s = session({ maxCalls: 10, maxRepairs: 3 });
  const wrapped = s.wrap(fakeAnthropic([anthropicResp('')]), {
    correct: [nonEmpty],
    repair: async () => { attempts++; return anthropicResp(''); }, // still broken
  });
  await assert.rejects(() => wrapped.messages.create({ model: 'm' }), /CHECK_FAILED/);
  assert.equal(attempts, 3, 'repair must stop at the bound, not loop forever');
});

test('repairs spend from the same budget: a repair can be refused by the gate', async () => {
  const s = session({ maxCalls: 1, maxRepairs: 5 });
  const wrapped = s.wrap(fakeAnthropic([anthropicResp('')]), {
    correct: [nonEmpty],
    repair: async () => anthropicResp('fixed'),
  });
  // 1 call spends maxCalls; the repair attempt hits the gate -> RUNAWAY
  await assert.rejects(() => wrapped.messages.create({ model: 'm' }), /RUNAWAY/);
});

// --- surfaces ----------------------------------------------------------------

test('OpenAI client shape is gated the same way', async () => {
  const s = session({ maxCalls: 1 });
  const wrapped = s.wrap(fakeOpenAI('hello'));
  const out = await wrapped.chat.completions.create({ model: 'gpt' });
  assert.equal(responseText(out), 'hello');
  await assert.rejects(() => wrapped.chat.completions.create({ model: 'gpt' }), /RUNAWAY/);
});

test('wrapFn gates arbitrary pipeline work', async () => {
  const s = session({ maxCalls: 2 });
  const parse = s.wrapFn('parse', async (x) => ({ n: Number(x) }), {
    correct: [(out) => Number.isFinite(out.n) || 'not a number'],
  });
  assert.deepEqual(await parse('42'), { n: 42 });
  await assert.rejects(() => parse('not-a-number'), /CHECK_FAILED/);
});

test('wrapped client passes through unrelated properties untouched', async () => {
  const client = fakeAnthropic([anthropicResp('x')]);
  client.apiKey = 'k';
  client.messages.list = () => 'listed';
  const s = session({ maxCalls: 5 });
  const wrapped = s.wrap(client);
  assert.equal(wrapped.apiKey, 'k');
  assert.equal(wrapped.messages.list(), 'listed');
});
