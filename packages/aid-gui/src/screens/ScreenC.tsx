import { useParams } from 'react-router-dom';
import { ScreenStub } from './ScreenStub';
import { MobileBackHeader } from '../components/shell/MobileBackHeader';
import { ProjectNotFound } from '../components/shell/ProjectNotFound';
import { useProjects } from '../components/shell/ProjectsContext';

/** EPIC Deep View. Filled in Phase 6. */
export function ScreenC() {
  const { project = '', epic = '' } = useParams();
  const { projects, loaded, error } = useProjects();
  const known = projects.some((p) => p.id === project);

  if (loaded && error) return <ProjectNotFound projectId={project} loadError />;
  if (loaded && !known) return <ProjectNotFound projectId={project} />;

  return (
    <>
      <MobileBackHeader title={`EPIC ${epic}`} />
      <ScreenStub title={`EPIC ${epic}`} todoStep="Step 43" />
    </>
  );
}
