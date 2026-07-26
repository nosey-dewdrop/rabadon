// rabadon repair/claude — the LLM-backed repair slot.
//
// This is the piece none of the field has (verified 26.07.2026): Langfuse and
// Braintrust only log, Galileo blocks or swaps in a canned response. Nobody
// REWRITES the broken output and re-checks it. rabadon's repair slot does —
// and the LLM inside it is still governed by rabadon's own laws:
//   - the repair spends from the SAME session budget (its real token usage
//     is counted, a runaway fixer is stopped by the same gate),
//   - the repaired output is re-run through the SAME correct[] checks; it is
//     accepted ONLY if the intent checks pass. The LLM gets no free pass.
//
// Zero dependencies: raw fetch to the Messages API. No SDK. The verdict on
// transport errors is deterministic: 400 = our bug, never retried; 429/5xx/529
// = transient, retried with backoff honoring retry-after; anything else after
// the retries = the repair FAILED, rabadon records it and fails closed.

const API_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-opus-4-8';
const RETRYABLE = new Set([429, 500, 529]);

/** One bounded call to the Messages API. Returns the full parsed response. */
async function callClaude({ system, user, maxTokens = 4096, apiKey, maxRetries = 2 }) {
  const key = apiKey || process.env.ANTHROPIC_API_KEY;
  if (!key) throw new Error('rabadon repair: no ANTHROPIC_API_KEY — the LLM repair slot is off without a key');

  let lastErr;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    let res;
    try {
      res = await fetch(API_URL, {
        method: 'POST',
        headers: {
          'x-api-key': key,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          model: MODEL,
          max_tokens: maxTokens,
          thinking: { type: 'adaptive' },
          system,
          messages: [{ role: 'user', content: user }],
        }),
      });
    } catch (err) {
      lastErr = new Error(`rabadon repair: network error: ${err.message}`);
      await backoff(attempt);
      continue;
    }

    if (res.ok) {
      const body = await res.json();
      if (body.stop_reason === 'refusal') throw new Error('rabadon repair: model refused the repair request');
      return body;
    }

    const errBody = await res.text().catch(() => '');
    if (!RETRYABLE.has(res.status)) {
      // 400/401/403/404: our request is wrong — retrying identical bytes is lying to ourselves
      throw new Error(`rabadon repair: API ${res.status} (not retryable): ${errBody.slice(0, 300)}`);
    }
    lastErr = new Error(`rabadon repair: API ${res.status}: ${errBody.slice(0, 200)}`);
    const retryAfter = Number(res.headers.get('retry-after'));
    await backoff(attempt, Number.isFinite(retryAfter) ? retryAfter * 1000 : undefined);
  }
  throw lastErr;
}

function backoff(attempt, hintMs) {
  const ms = hintMs != null ? hintMs : Math.min(8000, 500 * 2 ** attempt);
  return new Promise((r) => setTimeout(r, ms));
}

/** Pull the text out of a Messages API response's content blocks. */
function textOf(response) {
  return (response.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('');
}

const REPAIR_SYSTEM = `You are the repair slot inside rabadon, a reliability runtime for AI pipelines.
A pipeline step produced an output that FAILED its declared intent checks. Your only job is to produce a corrected output that satisfies every failed check.
Rules:
- Return ONLY the corrected output. No explanation, no preamble, no markdown fences.
- If the broken output is JSON, return valid JSON of the same shape, corrected.
- Do not invent data that is not derivable from the step's input. If a record is missing, restore it from the input; never fabricate records.
- Your output will be re-run through the same checks. If it fails, the pipeline stops. There is no partial credit.`;

/**
 * Build a repair function for rabadon's repair slot (pipeline step or wrap()).
 * Signature matches the slot: (brokenOutput, input, fails, ctx) => fixedOutput.
 *
 * The fixed output is returned in the same shape the step produced:
 *  - if broken was a provider response (has .content blocks), a response-shaped
 *    object is returned so wrap()'s checks re-run on it transparently;
 *  - otherwise the corrected data itself (JSON parsed back if broken was data).
 *
 * opts.onUsage: (usage) => void — called with the API usage object so the
 * caller can bank the REAL token spend against the session budget.
 */
export function claudeRepair(opts = {}) {
  return async function repair(broken, input, fails, ctx) {
    const brokenIsResponse = broken && Array.isArray(broken.content);
    const brokenPayload = brokenIsResponse ? textOf(broken) : JSON.stringify(broken, null, 2);

    const user = [
      `## The step's input`,
      '```json',
      JSON.stringify(input, null, 2).slice(0, 20000),
      '```',
      `## The broken output the step produced`,
      '```',
      String(brokenPayload).slice(0, 20000),
      '```',
      `## The intent checks that FAILED, with reasons`,
      ...fails.map((f) => `- ${f.check}: ${f.why}`),
      '',
      opts.instruction ? `## Extra repair context from the builder\n${opts.instruction}` : '',
      `Produce the corrected output now.`,
    ].join('\n');

    const response = await callClaude({
      system: REPAIR_SYSTEM,
      user,
      maxTokens: opts.maxTokens || 4096,
      apiKey: opts.apiKey,
      maxRetries: opts.maxRetries != null ? opts.maxRetries : 2,
    });

    if (opts.onUsage && response.usage) opts.onUsage(response.usage);

    const fixedText = textOf(response).trim();

    if (brokenIsResponse) {
      // hand back a response-shaped object: same shape the wrapped client
      // produced, so the correct[] checks re-run on it without special-casing.
      // usage carries the repair's REAL spend so the session budget counts it.
      return { ...broken, content: [{ type: 'text', text: fixedText }], usage: response.usage, rabadonRepaired: true };
    }
    if (typeof broken === 'string') return fixedText;
    try {
      return JSON.parse(stripFences(fixedText));
    } catch {
      throw new Error(`rabadon repair: model returned unparseable output for a data step: ${fixedText.slice(0, 160)}`);
    }
  };
}

function stripFences(s) {
  const m = s.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  return m ? m[1] : s;
}

export default { claudeRepair };
