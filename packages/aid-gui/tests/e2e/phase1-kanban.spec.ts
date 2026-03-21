/**
 * Phase 1 Kanban — Playwright smoke test.
 *
 * Validates that the Ideas to Execution kanban page renders correctly
 * with the expected 5 columns and the Insights panel tabs.
 *
 * This is intentionally a SMOKE test — it verifies visibility of key
 * UI elements without testing complex drag-and-drop interactions or
 * data mutations. Run with:
 *
 *   npx playwright test tests/e2e/phase1-kanban.spec.ts
 *
 * Requires a running dev server on port 3910 (see playwright.config.ts).
 */

import { test, expect } from '@playwright/test';

test.describe('Phase 1 Kanban — smoke test', () => {
  test('5 kanban columns are visible', async ({ page }) => {
    await page.goto('/ideas');

    // Verify all 5 columns are present
    const expectedColumns = ['Ideas', 'Plan', 'EPIC', 'Running', 'Done'];

    for (const column of expectedColumns) {
      const columnHeading = page.getByRole('heading', { name: column }).or(
        page.getByText(column, { exact: true }),
      );
      await expect(columnHeading).toBeVisible({ timeout: 10000 });
    }
  });

  test('Insights panel tabs are visible', async ({ page }) => {
    await page.goto('/ideas');

    // Verify the Backlog and Lessons tabs are present
    const backlogTab = page.getByRole('tab', { name: /backlog/i }).or(
      page.getByText('Backlog', { exact: true }),
    );
    const lessonsTab = page.getByRole('tab', { name: /lessons/i }).or(
      page.getByText('Lessons', { exact: true }),
    );

    await expect(backlogTab).toBeVisible({ timeout: 10000 });
    await expect(lessonsTab).toBeVisible({ timeout: 10000 });
  });
});
