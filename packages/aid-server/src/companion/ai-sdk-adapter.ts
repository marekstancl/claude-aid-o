/**
 * AI SDK Adapter — CompanionService backed by Vercel AI SDK + Claude Code provider.
 *
 * Uses `generateText()` and `streamText()` from the `ai` package together with
 * the `claudeCode()` provider from `ai-sdk-provider-claude-code`. These packages
 * are optional dependencies — they are imported dynamically at runtime so the
 * server can still boot without them (auto-detection falls through to the next
 * adapter in priority order).
 *
 * Authentication relies on the user's existing Claude subscription (Pro/Max).
 * No API key is required.
 */

import type {
  CompanionChunk,
  CompanionResponse,
  CompanionService,
  CompanionTools,
} from './types.js';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const DEFAULT_MODEL = 'sonnet';

// ---------------------------------------------------------------------------
// AiSdkAdapter
// ---------------------------------------------------------------------------

/**
 * Companion adapter that delegates to Vercel AI SDK with the Claude Code
 * community provider.
 *
 * Both `ai` and `ai-sdk-provider-claude-code` are loaded via dynamic
 * `import()` with variable-based specifiers so TypeScript does not attempt
 * static resolution (TS2307) on optional packages.
 */
export class AiSdkAdapter implements CompanionService {
  readonly name = 'ai-sdk' as const;

  private readonly modelId: string;

  constructor(modelId?: string) {
    this.modelId = modelId ?? DEFAULT_MODEL;
  }

  // -----------------------------------------------------------------------
  // CompanionService.send()
  // -----------------------------------------------------------------------

  async send(
    message: string,
    sessionId: string,
    systemPrompt?: string,
  ): Promise<CompanionResponse> {
    const { generateText } = await this.importAi();
    const model = await this.createModel();

    try {
      const result = await generateText({
        model,
        ...(systemPrompt ? { system: systemPrompt } : {}),
        prompt: message,
      });

      return {
        text: result.text,
        sessionId,
        model: result.response?.modelId ?? this.modelId,
        usage: result.usage
          ? {
              inputTokens: result.usage.inputTokens ?? 0,
              outputTokens: result.usage.outputTokens ?? 0,
            }
          : undefined,
      };
    } catch (error: unknown) {
      const errMsg =
        error instanceof Error ? error.message : 'Unknown error from AI SDK';
      throw new Error(`[ai-sdk-adapter] send() failed: ${errMsg}`);
    }
  }

  // -----------------------------------------------------------------------
  // CompanionService.stream()
  // -----------------------------------------------------------------------

  async *stream(
    message: string,
    sessionId: string,
    systemPrompt?: string,
    tools?: CompanionTools,
  ): AsyncGenerator<CompanionChunk> {
    const { streamText } = await this.importAi();
    const model = await this.createModel();

    try {
      const result = streamText({
        model,
        ...(systemPrompt ? { system: systemPrompt } : {}),
        prompt: message,
        ...(tools ? { tools, maxSteps: 8 } : {}),
      });

      // Iterate over the text stream, yielding incremental text chunks.
      for await (const textPart of result.textStream) {
        if (textPart) {
          yield { type: 'text', text: textPart };
        }
      }

      // After the stream completes, collect final metadata.
      const [usage, response] = await Promise.all([
        result.usage,
        result.response,
      ]);

      yield {
        type: 'done',
        sessionId,
        model: response?.modelId ?? this.modelId,
        usage: usage
          ? {
              inputTokens: usage.inputTokens ?? 0,
              outputTokens: usage.outputTokens ?? 0,
            }
          : undefined,
      };
    } catch (error: unknown) {
      const errMsg =
        error instanceof Error ? error.message : 'Unknown error from AI SDK';
      throw new Error(`[ai-sdk-adapter] stream() failed: ${errMsg}`);
    }
  }

  // -----------------------------------------------------------------------
  // CompanionService.isAvailable()
  // -----------------------------------------------------------------------

  async isAvailable(): Promise<boolean> {
    try {
      const { generateText } = await this.importAi();
      await this.importProvider();
      const model = await this.createModel();

      // Do a lightweight probe to verify auth works end-to-end.
      // The ai-sdk-provider-claude-code returns "Not logged in · Please run
      // /login" as regular text (not an error) when credentials are missing.
      // Wrap in a 5-second timeout to prevent hanging when the provider
      // cannot reach Claude (e.g. Docker without authentication).
      const probe = await Promise.race([
        (generateText as Function)({
          model,
          prompt: 'ping',
          maxTokens: 10,
        }),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('probe timeout')), 5_000),
        ),
      ]);
      const text: string = (probe as AiGenerateResult)?.text ?? '';
      if (text.includes('Not logged in') || text.includes('/login')) {
        return false;
      }

      return true;
    } catch {
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // Private — dynamic imports
  // -----------------------------------------------------------------------

  /**
   * Dynamically import the `ai` package.
   *
   * The module specifier is assigned to a local variable so TypeScript's
   * static analysis does not try to resolve the optional dependency at
   * compile time (avoids TS2307).
   */
  private async importAi(): Promise<{
    generateText: (...args: unknown[]) => Promise<AiGenerateResult>;
    streamText: (...args: unknown[]) => AiStreamResult;
  }> {
    const aiPkg = 'ai';
    // eslint-disable-next-line @typescript-eslint/no-unsafe-return
    return await import(/* @vite-ignore */ aiPkg);
  }

  /**
   * Dynamically import the `ai-sdk-provider-claude-code` package.
   */
  private async importProvider(): Promise<{
    claudeCode: (modelId: string) => unknown;
  }> {
    const providerPkg = 'ai-sdk-provider-claude-code';
    // eslint-disable-next-line @typescript-eslint/no-unsafe-return
    return await import(/* @vite-ignore */ providerPkg);
  }

  /**
   * Create the language model instance from the provider.
   */
  private async createModel(): Promise<unknown> {
    const { claudeCode } = await this.importProvider();
    return claudeCode(this.modelId);
  }
}

// ---------------------------------------------------------------------------
// Internal type aliases — minimal shapes for dynamic import results.
// These avoid importing types from the `ai` package (which is optional).
// ---------------------------------------------------------------------------

interface AiUsage {
  inputTokens?: number;
  outputTokens?: number;
}

interface AiResponseMeta {
  modelId?: string;
}

interface AiGenerateResult {
  text: string;
  usage?: AiUsage;
  response?: AiResponseMeta;
}

interface AiStreamResult {
  textStream: AsyncIterable<string>;
  usage: Promise<AiUsage | undefined>;
  response: Promise<AiResponseMeta | undefined>;
}
