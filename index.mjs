// rabadon — public entry. The core stays pure; this file wires the live bus.
//
//   import { pipeline, session, named } from './index.mjs';
//
//   pipeline('my-pipe').step(...).bound(...).run(input)   // declared pipeline
//   session({ maxTokens: 200_000 }).wrap(new Anthropic()) // wrap existing code
//
// Either way, every step streams live to `rabadon watch` in another terminal.

import { pipeline as corePipeline, named } from './core/rabadon.mjs';
import { session as coreSession, RabadonStop, responseText } from './core/wrap.mjs';
import { emitter } from './core/bus.mjs';

/** A pipeline whose run streams to the live bus. */
export function pipeline(name) {
  const pipe = typeof name === 'string' && name ? name : 'pipeline';
  return corePipeline({ name: pipe, emit: emitter({ pipe }) });
}

/** A budget session whose gated calls stream to the live bus. */
export function session(opts = {}) {
  const pipe = opts.name || 'session';
  return coreSession({ ...opts, emit: opts.emit || emitter({ pipe }) });
}

export { named, RabadonStop, responseText };
export default { pipeline, session, named, RabadonStop, responseText };
