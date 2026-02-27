/**
 * CLI Proxy Adapter — Companion backend that delegates to the `claude` CLI.
 *
 * Spawns `claude -p --output-format stream-json --verbose --max-turns 1`
 * as a child process, pipes the user message via stdin, and parses the
 * resulting NDJSON output. This lets the GUI companion work on any machine
 * that has the Claude Code CLI installed, without needing the ai-sdk
 * provider packages.
 *
 * IMPORTANT: Environment variables `CLAUDECODE` and `CLAUDE_CODE_ENTRYPOINT`
 * are stripped from the child's env to prevent Claude from detecting a nested
 * session and changing its behavior.
 */

import { spawn, execFile } from 'node:child_process';
import { createInterface } from 'node:readline';
import { promisify } from 'node:util';

import type {
  CompanionChunk,
  CompanionResponse,
  CompanionService,
  TokenUsage,
} from './types.js';

const execFileAsync = promisify(execFile);

// ---------------------------------------------------------------------------
// NDJSON line shapes emitted by `claude --output-format stream-json`
// ---------------------------------------------------------------------------

/**
 * Content block inside an assistant message.
 * The CLI emits `{"type": "text", "text": "..."}` blocks inside the
 * `message.content` array.
 */
interface ContentBlockText {
  type: 'text';
  text: string;
}

/**
 * An assistant-type NDJSON line wrapping a full message object.
 * The `message.content` array contains one or more content blocks.
 */
interface AssistantLine {
  type: 'assistant';
  message: {
    content: ContentBlockText[];
    model?: string;
    usage?: { input_tokens?: number; output_tokens?: number };
  };
}

/**
 * A result-type NDJSON line containing the final concatenated result text.
 */
interface ResultLine {
  type: 'result';
  result: string;
  model?: string;
  usage?: { input_tokens?: number; output_tokens?: number };
  session_id?: string;
}

/** Union of known NDJSON line shapes. */
type NdjsonLine = AssistantLine | ResultLine | { type: string };

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Build a sanitised copy of `process.env` that won't trigger nested-session
 * detection inside the spawned `claude` process.
 */
function cleanEnv(): NodeJS.ProcessEnv {
  const env = { ...process.env };
  delete env.CLAUDECODE;
  delete env.CLAUDE_CODE_ENTRYPOINT;
  return env;
}

/**
 * Build the CLI argument list.
 *
 * Flags:
 *   -p              — print mode (read from stdin, write to stdout)
 *   --output-format stream-json — NDJSON output
 *   --verbose       — include usage/model metadata in output
 *   --max-turns 1   — single turn (no tool loops)
 */
function buildArgs(systemPrompt?: string): string[] {
  const args = [
    '-p',
    '--output-format', 'stream-json',
    '--verbose',
    '--max-turns', '1',
  ];

  if (systemPrompt) {
    args.push('--system-prompt', systemPrompt);
  }

  return args;
}

/**
 * Attempt to parse a single NDJSON line. Returns `null` for blank or
 * malformed lines so the caller can skip them without crashing.
 */
function parseLine(raw: string): NdjsonLine | null {
  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;

  try {
    return JSON.parse(trimmed) as NdjsonLine;
  } catch {
    return null;
  }
}

/**
 * Extract text content from an assistant-type NDJSON line.
 * Returns the concatenation of all `text` content blocks.
 */
function extractAssistantText(line: AssistantLine): string {
  if (!line.message?.content) return '';
  return line.message.content
    .filter((block): block is ContentBlockText => block.type === 'text')
    .map((block) => block.text)
    .join('');
}

/**
 * Extract token usage from a line that may carry it.
 */
function extractUsage(
  raw: { input_tokens?: number; output_tokens?: number } | undefined,
): TokenUsage | undefined {
  if (!raw) return undefined;
  if (raw.input_tokens === undefined && raw.output_tokens === undefined) {
    return undefined;
  }
  return {
    inputTokens: raw.input_tokens ?? 0,
    outputTokens: raw.output_tokens ?? 0,
  };
}

// ---------------------------------------------------------------------------
// CliProxyAdapter
// ---------------------------------------------------------------------------

/**
 * Companion adapter that delegates to the locally-installed `claude` CLI.
 *
 * This is the fallback adapter used when the ai-sdk provider packages are
 * not available but the user has Claude Code installed.
 */
export class CliProxyAdapter implements CompanionService {
  readonly name = 'cli-proxy' as const;

  // -----------------------------------------------------------------------
  // send() — blocking request/response
  // -----------------------------------------------------------------------

  async send(
    message: string,
    sessionId: string,
    systemPrompt?: string,
  ): Promise<CompanionResponse> {
    const args = buildArgs(systemPrompt);

    return new Promise<CompanionResponse>((resolve, reject) => {
      const child = spawn('claude', args, {
        env: cleanEnv(),
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      let resultText = '';
      let model: string | undefined;
      let usage: TokenUsage | undefined;
      let stderrBuf = '';

      // -- stdout: accumulate NDJSON lines ---------------------------------
      const rl = createInterface({ input: child.stdout, crlfDelay: Infinity });

      rl.on('line', (raw) => {
        const parsed = parseLine(raw);
        if (!parsed) return;

        if (parsed.type === 'result') {
          const resultLine = parsed as ResultLine;
          resultText = resultLine.result ?? '';
          model = resultLine.model ?? model;
          usage = extractUsage(resultLine.usage) ?? usage;
        } else if (parsed.type === 'assistant') {
          const assistantLine = parsed as AssistantLine;
          // Accumulate in case there is no result line
          const chunk = extractAssistantText(assistantLine);
          if (chunk) resultText += chunk;
          model = assistantLine.message?.model ?? model;
          usage = extractUsage(assistantLine.message?.usage) ?? usage;
        }
      });

      // -- stderr: capture for error reporting -----------------------------
      child.stderr.on('data', (data: Buffer) => {
        stderrBuf += data.toString();
      });

      // -- Process lifecycle -----------------------------------------------
      child.on('error', (err) => {
        reject(new Error(`Failed to spawn claude CLI: ${err.message}`));
      });

      child.on('close', (code) => {
        if (code !== 0 && code !== null) {
          const detail = stderrBuf.trim() || `exit code ${code}`;
          reject(new Error(`claude CLI exited with code ${code}: ${detail}`));
          return;
        }

        resolve({
          text: resultText || '(No response from claude CLI)',
          sessionId,
          model,
          usage,
        });
      });

      // -- Feed the message via stdin and close ----------------------------
      child.stdin.write(message);
      child.stdin.end();
    });
  }

  // -----------------------------------------------------------------------
  // stream() — async generator of CompanionChunks
  // -----------------------------------------------------------------------

  async *stream(
    message: string,
    sessionId: string,
    systemPrompt?: string,
  ): AsyncGenerator<CompanionChunk> {
    const args = buildArgs(systemPrompt);

    const child = spawn('claude', args, {
      env: cleanEnv(),
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    let model: string | undefined;
    let usage: TokenUsage | undefined;
    let stderrBuf = '';

    // Capture stderr in background
    child.stderr.on('data', (data: Buffer) => {
      stderrBuf += data.toString();
    });

    // Set up line-by-line NDJSON reading on stdout
    const rl = createInterface({ input: child.stdout, crlfDelay: Infinity });

    // We need to bridge the readline event-based API into an async iterator.
    // Collect lines in a queue and resolve waiting consumers.
    const lineQueue: string[] = [];
    let lineDone = false;
    let lineError: Error | null = null;
    let lineResolve: (() => void) | null = null;

    rl.on('line', (raw) => {
      lineQueue.push(raw);
      if (lineResolve) {
        const r = lineResolve;
        lineResolve = null;
        r();
      }
    });

    rl.on('close', () => {
      lineDone = true;
      if (lineResolve) {
        const r = lineResolve;
        lineResolve = null;
        r();
      }
    });

    rl.on('error', (err) => {
      lineError = err;
      lineDone = true;
      if (lineResolve) {
        const r = lineResolve;
        lineResolve = null;
        r();
      }
    });

    child.on('error', (err) => {
      lineError = new Error(`Failed to spawn claude CLI: ${err.message}`);
      lineDone = true;
      if (lineResolve) {
        const r = lineResolve;
        lineResolve = null;
        r();
      }
    });

    // Track exit code for error reporting after stream ends
    let exitCode: number | null = null;
    child.on('close', (code) => {
      exitCode = code;
    });

    // Feed the message via stdin and close
    child.stdin.write(message);
    child.stdin.end();

    // Consume lines as they arrive
    while (true) {
      // Wait for a line or completion
      if (lineQueue.length === 0 && !lineDone) {
        await new Promise<void>((resolve) => {
          lineResolve = resolve;
        });
      }

      // Drain all queued lines before checking done
      while (lineQueue.length > 0) {
        const raw = lineQueue.shift()!;
        const parsed = parseLine(raw);
        if (!parsed) continue;

        if (parsed.type === 'result') {
          const resultLine = parsed as ResultLine;
          if (resultLine.result) {
            yield { type: 'text', text: resultLine.result };
          }
          model = resultLine.model ?? model;
          usage = extractUsage(resultLine.usage) ?? usage;
        } else if (parsed.type === 'assistant') {
          const assistantLine = parsed as AssistantLine;
          const chunk = extractAssistantText(assistantLine);
          if (chunk) {
            yield { type: 'text', text: chunk };
          }
          model = assistantLine.message?.model ?? model;
          usage = extractUsage(assistantLine.message?.usage) ?? usage;
        }
        // Other line types (e.g. system, tool_use) are silently skipped
      }

      if (lineDone) break;
    }

    // Check for errors
    if (lineError) {
      throw lineError;
    }

    // Wait briefly for the child process to fully close if it hasn't yet
    if (exitCode === null) {
      await new Promise<void>((resolve) => {
        child.on('close', () => resolve());
      });
    }

    if (exitCode !== 0 && exitCode !== null) {
      const detail = stderrBuf.trim() || `exit code ${exitCode}`;
      throw new Error(`claude CLI exited with code ${exitCode}: ${detail}`);
    }

    // Yield final done sentinel
    yield { type: 'done', sessionId, model, usage };
  }

  // -----------------------------------------------------------------------
  // isAvailable() — probe for `claude` on PATH
  // -----------------------------------------------------------------------

  async isAvailable(): Promise<boolean> {
    try {
      await execFileAsync('which', ['claude']);
      return true;
    } catch {
      return false;
    }
  }
}
