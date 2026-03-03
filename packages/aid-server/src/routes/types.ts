/** Shared route parameter types and validation utilities. */

/** Validates a path component is safe to use in file system operations (CWE-22). */
export function isValidPathComponent(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    value.length > 0 &&
    !value.includes('/') &&
    !value.includes('\\') &&
    !value.includes('\0') &&
    value !== '..' &&
    value !== '.'
  );
}

export interface ProjectParams {
  projectId: string;
  [key: string]: string;
}

export interface EpicParams extends ProjectParams {
  epicId: string;
}

export interface IdeaParams extends ProjectParams {
  ideaId: string;
}

export interface EvidenceFileParams extends ProjectParams {
  epicId: string;
  runId: string;
  '0': string; // wildcard path
}

export interface IdeaLinkBody {
  linkedPlan?: string;
  linkedEpic?: string;
}
