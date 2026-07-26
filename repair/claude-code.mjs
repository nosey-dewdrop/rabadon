// rabadon repair/claude-code — the LLM repair slot, driven by the local
// Claude Code CLI instead of an API key.
//
// Why this exists: the repair slot (repair/claude.mjs) needs ANTHROPIC_API_KEY.
// But on a machine where Claude Code is installed and logged in, there is
// ALREADY a valid Claude authorization — the builder's own subscription.
// `claude -p` runs headless, takes a prompt on stdin, prints the answer.
// So the repair slot works with zero setup on any Claude Code machine.
//
// The laws are identical to the API-backed slot:
//   - the repaired output is re-run through the SAME correct[] checks,
//     accepted ONLY if they pass — the LLM gets no free pass;
//   - the call is bounded by a hard timeout, so a hung CLI cannot become
//     the very runaway rabadon exists to kill;
//   - on any failure (CLI missing, timeout, unparseable output) the repair
//     FAILS and rabadon fails closed. No silent passes.
//
// Zero dependencies: node:child_process only.

import { execFile } from 'node:child_process';

const REPAIR_SYSTEM = `You are the repair slot inside rabadon, a reliability runtime for AI pipelines.
A pipeline step produced an output that FAILED its declared intent checks. Your only job is to produce a corrected output that satisfies every failed check.
Rules:
- Return ONLY the corrected output. No explanation, no preamble, no markdown fences.
- If the broken output is JSON, return valid JSON of the same shape, corrected.
- Do not invent data that is not derivable from the step's input. If a record is missing, restore it from the input; never fabricate records.
- Your output will be re-run through the same checks. If it fails, the pipeline stops. There is no partial credit.`;

function runClaudeCode(prompt, { timeoutMs = 120000, bin = 'claude' } = {}) {
  return new Promise((resolve, reject) => {
    const child = execFile(
      bin,
      ['-p', '--output-format', 'text'],
      { timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024 },
      (err, stdout, stderr) => {
        if (err) {
          const why = err.killed ? `timed out after ${timeoutMs}ms` : (stderr || err.message).slice(0, 200);
          reject(new Error(`rabadon repair (claude-code): ${why}`));
          return;
        }
        resolve(String(stdout).trim());
      },
    );
    child.stdin.write(prompt);
    child.stdin.end();
  });
}

/**
 * Build a repair function backed by the local Claude Code CLI.
 * Same slot signature as claudeRepair: (broken, input, fails, ctx) => fixed.
 */
export function claudeCodeRepair(opts = {}) {
  return async function repair(broken, input, fails) {
    const brokenIsResponse = broken && Array.isArray(broken.content);
    const brokenPayload = brokenIsResponse
      ? broken.content.filter((b) => b.type === 'text').map((b) => b.text).join('')
      : JSON.stringify(broken, null, 2);

    const prompt = [
      REPAIR_SYSTEM,
      '',
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
      opts.instruction ? `## Extra repair context from the builder\n${opts.instruction}\n` : '',
      `Produce the corrected output now.`,
    ].join('\n');

    const fixedText = await runClaudeCode(prompt, opts);

    if (brokenIsResponse) {
      return { ...broken, content: [{ type: 'text', text: fixedText }], rabadonRepaired: true };
    }
    if (typeof broken === 'string') return fixedText;
    try {
      const m = fixedText.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
      return JSON.parse(m ? m[1] : fixedText);
    } catch {
      throw new Error(`rabadon repair (claude-code): model returned unparseable output for a data step: ${fixedText.slice(0, 160)}`);
    }
  };
}

export default { claudeCodeRepair };
