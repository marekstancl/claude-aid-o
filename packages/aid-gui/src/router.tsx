import type { ReactElement } from 'react';
import { createBrowserRouter } from 'react-router-dom';
import App from './App';
import { ErrorBoundary } from './components/ErrorBoundary';
import { ScreenG } from './screens/ScreenG';
import { ScreenA } from './screens/ScreenA';
import { ScreenB } from './screens/ScreenB';
import { ScreenPlan } from './screens/ScreenPlan';
import { ScreenC } from './screens/ScreenC';
import { ScreenD } from './screens/ScreenD';
import { ScreenE } from './screens/ScreenE';
import { ScreenF } from './screens/ScreenF';

/** Wrap each route element in the salvaged ErrorBoundary so a bad param or a
 *  screen render crash degrades gracefully instead of taking down the shell. */
const guard = (el: ReactElement) => <ErrorBoundary>{el}</ErrorBoundary>;

/**
 * Route table for the G→A→B→{Plan,C} drill spine plus the D/E/F siblings.
 * App is the layout route (renders Sidebar/BottomTabBar/Breadcrumb + <Outlet/>).
 */
export const router = createBrowserRouter([
  {
    path: '/',
    element: <App />,
    children: [
      { index: true, element: guard(<ScreenG />) },
      { path: 'prehled', element: guard(<ScreenA />) },
      { path: 'p/:project', element: guard(<ScreenB />) },
      { path: 'p/:project/plans/:planId', element: guard(<ScreenPlan />) },
      { path: 'p/:project/e/:epic', element: guard(<ScreenC />) },
      { path: 'activity', element: guard(<ScreenD />) },
      { path: 'compliance', element: guard(<ScreenE />) },
      { path: 'help', element: guard(<ScreenF />) },
    ],
  },
]);
