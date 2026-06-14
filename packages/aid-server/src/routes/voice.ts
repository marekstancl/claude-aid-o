/**
 * Voice routes — Whisper API proxy for voice dictation.
 *
 * Endpoints:
 *   POST /api/p/:projectId/companion/transcribe — Transcribe audio via OpenAI Whisper
 */

import { Router, type Request, type Response, type RequestHandler } from 'express';
import multer from 'multer';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';

// ---------------------------------------------------------------------------
// Multer config — in-memory storage, 25 MB limit
// ---------------------------------------------------------------------------

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 25 * 1024 * 1024 }, // 25 MB
});

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// LiteLLM proxy (D-082): default přes svc-litellm, ne přímo na OpenAI.
const WHISPER_API_URL =
  process.env.WHISPER_API_URL ||
  'http://svc-litellm:8830/v1/audio/transcriptions';
const WHISPER_MODEL = process.env.WHISPER_MODEL || 'whisper';
const WHISPER_TIMEOUT_MS = 60_000; // 60 seconds

// ---------------------------------------------------------------------------
// Route factory
// ---------------------------------------------------------------------------

export function voiceRoutes(_registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // -------------------------------------------------------------------------
  // POST /transcribe — Transcribe audio via OpenAI Whisper API
  // -------------------------------------------------------------------------
  router.post(
    '/transcribe',
    upload.single('file') as unknown as RequestHandler,
    async (req: Request<ProjectParams>, res: Response) => {
      // 1. Check LiteLLM proxy key availability (fallback OPENAI_API_KEY pro BC)
      const apiKey = process.env.LITELLM_API_KEY || process.env.OPENAI_API_KEY;
      if (!apiKey) {
        return res.status(503).json({
          ok: false,
          error: {
            code: 'SERVICE_UNAVAILABLE',
            message:
              'Whisper API not configured. Set LITELLM_API_KEY (LiteLLM proxy) environment variable.',
          },
        });
      }

      // 2. Validate uploaded file
      const file = req.file;
      if (!file) {
        return res.status(400).json({
          ok: false,
          error: {
            code: 'BAD_REQUEST',
            message:
              'No audio file provided. Send a multipart form with a "file" field.',
          },
        });
      }

      // 3. Build FormData for Whisper API
      const formData = new FormData();
      formData.append(
        'file',
        new Blob([new Uint8Array(file.buffer)], { type: file.mimetype }),
        file.originalname || 'audio.webm',
      );
      formData.append('model', WHISPER_MODEL);

      // 4. Call Whisper API
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(
          () => controller.abort(),
          WHISPER_TIMEOUT_MS,
        );

        const response = await fetch(WHISPER_API_URL, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${apiKey}`,
          },
          body: formData,
          signal: controller.signal,
        });

        clearTimeout(timeoutId);

        // 5. Handle Whisper API error responses
        if (!response.ok) {
          const errorBody = await response.text();
          let errorMessage: string;
          let errorCode: string;

          switch (response.status) {
            case 401:
              errorCode = 'AUTH_ERROR';
              errorMessage =
                'OpenAI API key is invalid or expired. Check OPENAI_API_KEY.';
              break;
            case 429:
              errorCode = 'RATE_LIMITED';
              errorMessage =
                'OpenAI API rate limit exceeded. Please try again later.';
              break;
            case 413:
              errorCode = 'FILE_TOO_LARGE';
              errorMessage = 'Audio file exceeds OpenAI size limit.';
              break;
            default: {
              errorCode = 'TRANSCRIPTION_FAILED';
              // Try to extract message from JSON error body
              try {
                const parsed = JSON.parse(errorBody);
                errorMessage =
                  parsed.error?.message || `Whisper API error: ${response.status}`;
              } catch {
                errorMessage = `Whisper API error: ${response.status}`;
              }
            }
          }

          return res.status(response.status >= 500 ? 502 : response.status).json({
            ok: false,
            error: { code: errorCode, message: errorMessage },
          });
        }

        // 6. Parse successful response
        const result = (await response.json()) as { text: string };

        return res.json({
          ok: true,
          data: { text: result.text },
        });
      } catch (err: unknown) {
        // Handle timeout / network errors
        if (err instanceof Error && err.name === 'AbortError') {
          return res.status(504).json({
            ok: false,
            error: {
              code: 'TIMEOUT',
              message: 'Whisper API request timed out.',
            },
          });
        }

        const message =
          err instanceof Error ? err.message : 'Unknown transcription error';
        return res.status(502).json({
          ok: false,
          error: {
            code: 'TRANSCRIPTION_FAILED',
            message: `Failed to contact Whisper API: ${message}`,
          },
        });
      }
    },
  );

  return router;
}
