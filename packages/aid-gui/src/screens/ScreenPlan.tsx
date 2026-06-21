import { useParams } from 'react-router-dom';
import { ScreenStub } from './ScreenStub';
import { MobileBackHeader } from '../components/shell/MobileBackHeader';
import { ProjectNotFound } from '../components/shell/ProjectNotFound';
import { useProjects } from '../components/shell/ProjectsContext';

/** Plán detail (tabbed). Filled in Phase 6. */
export function ScreenPlan() {
  const { project = '', planId = '' } = useParams();
  const { projects, loaded } = useProjects();
  const known = projects.some((p) => p.id === project);

  if (loaded && !known) return <ProjectNotFound projectId={project} />;

  return (
    <>
      <MobileBackHeader title={`Plán ${planId}`} />
      <ScreenStub title={`Plán ${planId}`} todoStep="Step 39" />
    </>
  );
}
