/** Shared route parameter types. */

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
