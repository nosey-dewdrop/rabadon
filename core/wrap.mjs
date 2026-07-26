// rabadon wrap — one line into an existing codebase, and every LLM call
// becomes a checked, bounded, self-repairing step.
//
//   import { session } from 'rabadon';
//   const s = session({ maxCalls: 50, maxTokens: 200_000, maxRepairs: 2 });
//   const client = s.wrap(new Anthropic(), {
//     correct: [named('non-empty', (out) => out.text.length > 0 || 'empty completion')],
//   });
//   // use `client` exactly like before — rabadon now sits INSIDE every call.
//
// Where this shape comes from (verified against the field, 26.07.2026):
//   - Langfuse `observeOpenAI(client)` / Braintrust `wrapOpenAI(client)`:
//     the one-line client wrap is the adoption surface that works — BUT both
//     are passive; their own docs say they only log, never gate.
//   - Galileo Protect / Agent Control: the only inline one — code AWAITS the
//     verdict, then branches (allow / deny / canned override). No rewrite.
//   - rabadon: the wrap surface of the passive tools, the inline gate of
//     Galileo, plus the piece none of them have — bounded REPAIR, re-checked
//     before anything flows onward. Fail-closed.
//
// The session is the unit of protection: one shared budget across every call
// made through it, so a runaway loop cannot spend past the bound no matter
// how many wrapped clients it touches. Bound is enforced PRE-CALL (the spend
// is refused before it happens, not lamented after).

import { EV } from './bus.mjs';

/** Error thrown when rabadon refuses to let a call proceed or flow onward. */
export class RabadonStop extends Error {
  constructor(reason, detail, extra = {}) {
    super(`rabadon ${reason}: ${detail}`);
    this.name = 'RabadonStop';
    this.reason = reason;   // 'RUNAWAY' | 'CHECK_FAILED'
    this.detail = detail;
    Object.assign(this, extra);
  }
}

function usageTokens(response) {
  // Anthropic: response.usage = { input_tokens, output_tokens }
  // OpenAI:    response.usage = { prompt_tokens, completion_tokens, total_tokens }
  const u = response && response.usage;
  if (!u) return 0;
  if (Number.isFinite(u.total_tokens)) return u.total_tokens;
  return (u.input_tokens || u.prompt_tokens || 0) + (u.output_tokens || u.completion_tokens || 0);
}

/** Read the assistant text out of either provider's response shape. */
export function responseText(response) {
  if (!response) return '';
  if (Array.isArray(response.content)) {
    // Anthropic: content blocks
    return response.content.filter((b) => b.type === 'text').map((b) => b.text).join('');
  }
  if (Array.isArray(response.choices)) {
    // OpenAI: choices[0].message.content
    const m = response.choices[0] && response.choices[0].message;
    return (m && m.content) || '';
  }
  return '';
}

async function runChecks(correct, response, request, ctx) {
  const fails = [];
  for (let i = 0; i < correct.length; i++) {
    const name = correct[i].checkName || `check#${i}`;
    let v;
    try { v = await correct[i](response, request, ctx); }
    catch (err) { fails.push({ check: name, why: `${name} threw: ${String(err && err.message || err).slice(0, 160)}` }); continue; }
    if (v === true) continue;
    if (typeof v === 'string') { fails.push({ check: name, why: v }); continue; }
    if (v && typeof v === 'object' && 'ok' in v) { if (!v.ok) fails.push({ check: name, why: v.why || `${name} failed` }); continue; }
    // no verdict = fail closed, same law as the core
    fails.push({ check: name, why: `${name} returned no verdict (fail-closed)` });
  }
  return fails;
}

/**
 * A session: one budget, many wrapped clients/functions.
 * @param {object} opts
 * @param {number} [opts.maxCalls]   hard cap on LLM calls through this session
 * @param {number} [opts.maxTokens]  hard cap on tokens (real provider usage counts)
 * @param {number} [opts.maxRepairs] per-call repair bound (default 0 = no repair)
 * @param {'block'|'observe'} [opts.mode] 'block' (default): a failed call throws
 *   RabadonStop so nothing broken flows onward. 'observe': log + count only —
 *   the Langfuse mode, for the first day in an existing codebase.
 * @param {(ev:string, fields:object)=>void} [opts.emit] live event stream hook
 */
export function session(opts = {}) {
  if (!opts.maxCalls && !opts.maxTokens) {
    throw new Error('rabadon session: set at least one of maxCalls/maxTokens — an unbounded session is a runaway waiting to happen');
  }
  const emit = opts.emit || (() => {});
  const mode = opts.mode || 'block';
  const state = { calls: 0, tokens: 0, blocked: 0, repaired: 0, observedFails: 0 };

  function gate(label) {
    if (opts.maxCalls != null && state.calls >= opts.maxCalls) {
      emit(EV.STOP, { reason: 'RUNAWAY', detail: `maxCalls=${opts.maxCalls} reached before ${label}` });
      throw new RabadonStop('RUNAWAY', `maxCalls=${opts.maxCalls} reached — refusing "${label}" (spent: ${state.calls} calls, ${state.tokens} tokens)`);
    }
    if (opts.maxTokens != null && state.tokens >= opts.maxTokens) {
      emit(EV.STOP, { reason: 'RUNAWAY', detail: `maxTokens=${opts.maxTokens} spent before ${label}` });
      throw new RabadonStop('RUNAWAY', `maxTokens=${opts.maxTokens} spent — refusing "${label}" (spent: ${state.tokens} tokens in ${state.calls} calls)`);
    }
  }

  /**
   * Gate one raw call. The engine under both wrap() and wrapFn().
   * @param {string} label
   * @param {() => Promise<any>} doCall     performs the actual provider call
   * @param {object} request                what was asked (for checks/repair)
   * @param {object} per                    { correct[], repair, maxRepairs }
   */
  async function gated(label, doCall, request, per = {}) {
    gate(label);
    state.calls += 1;
    emit(EV.STEP_START, { step: label, calls: state.calls, tokens: state.tokens });

    let response = await doCall();
    state.tokens += usageTokens(response);

    const correct = per.correct || [];
    let fails = await runChecks(correct, response, request, { session: state });
    if (fails.length) emit(EV.CHECK_FAIL, { step: label, fails });

    const maxRepairs = per.maxRepairs != null ? per.maxRepairs : (opts.maxRepairs || 0);
    let attempt = 0;
    while (fails.length && per.repair && attempt < maxRepairs) {
      attempt += 1;
      gate(`${label}#repair${attempt}`); // repairs spend from the SAME budget
      emit(EV.REPAIR_START, { step: label, attempt, fixing: fails.map((f) => f.check) });
      let fixed;
      try {
        fixed = await per.repair(response, request, fails, { session: state });
      } catch (err) {
        emit(EV.REPAIR_FAIL, { step: label, attempt, why: String(err && err.message || err).slice(0, 200) });
        break;
      }
      state.tokens += usageTokens(fixed) || 0;
      const reFails = await runChecks(correct, fixed, request, { session: state });
      emit(reFails.length ? EV.REPAIR_FAIL : EV.REPAIR_OK, { step: label, attempt, remaining: reFails.map((f) => f.why) });
      response = fixed;
      if (reFails.length === 0) state.repaired += 1;
      fails = reFails;
    }

    if (fails.length) {
      if (mode === 'block') {
        state.blocked += 1;
        emit(EV.STOP, { reason: 'CHECK_FAILED', detail: `${label}: ${fails.map((f) => f.check).join(', ')}` });
        throw new RabadonStop('CHECK_FAILED', `${label}: ${fails.map((f) => `${f.check} (${f.why})`).join('; ')}`, { fails, response });
      }
      state.observedFails += 1; // observe mode: it flows, but it is ON RECORD
    }

    emit(EV.STEP_OK, { step: label, tokens: state.tokens, repaired: attempt > 0 && fails.length === 0 });
    return response;
  }

  /**
   * Wrap a provider client (Anthropic or OpenAI SDK instance). Returns a
   * proxy that behaves identically except every completion call is gated.
   */
  function wrap(client, per = {}) {
    if (client && client.messages && typeof client.messages.create === 'function') {
      // Anthropic shape
      const original = client.messages.create.bind(client.messages);
      const messages = new Proxy(client.messages, {
        get(t, k) {
          if (k === 'create') {
            return (params, ...rest) =>
              gated(per.label || `anthropic:${params && params.model || 'messages'}`, () => original(params, ...rest), params, per);
          }
          const v = t[k];
          return typeof v === 'function' ? v.bind(t) : v;
        },
      });
      return new Proxy(client, { get(t, k) { return k === 'messages' ? messages : t[k]; } });
    }
    if (client && client.chat && client.chat.completions && typeof client.chat.completions.create === 'function') {
      // OpenAI shape
      const original = client.chat.completions.create.bind(client.chat.completions);
      const completions = new Proxy(client.chat.completions, {
        get(t, k) {
          if (k === 'create') {
            return (params, ...rest) =>
              gated(per.label || `openai:${params && params.model || 'chat'}`, () => original(params, ...rest), params, per);
          }
          const v = t[k];
          return typeof v === 'function' ? v.bind(t) : v;
        },
      });
      const chat = new Proxy(client.chat, { get(t, k) { return k === 'completions' ? completions : t[k]; } });
      return new Proxy(client, { get(t, k) { return k === 'chat' ? chat : t[k]; } });
    }
    throw new Error('rabadon wrap: unrecognized client — expected an Anthropic (.messages.create) or OpenAI (.chat.completions.create) SDK instance');
  }

  /** Wrap any async function as a gated step (non-LLM pipeline work). */
  function wrapFn(label, fn, per = {}) {
    return async (...args) => gated(label, () => fn(...args), args[0], per);
  }

  return {
    wrap,
    wrapFn,
    /** Live spend/verdict counters — data, not a claim. */
    stats: () => ({ ...state }),
  };
}

export default { session, RabadonStop, responseText };
