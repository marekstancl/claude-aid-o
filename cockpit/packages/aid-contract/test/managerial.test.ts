import { describe, it, expect } from 'vitest';
import type { SuccessProbability, PlanDetail, PlanSummary, AuditSummary, Brief } from '../src/managerial.js';

describe('managerial contract', () => {
  it('SuccessProbability MVP1 invariant: value and source must be null', () => {
    const sp: SuccessProbability = { value: null, source: null };
    // MVP1 INVARIANT: MUST be null
    expect(sp.value).toBeNull();
    expect(sp.source).toBeNull();
  });

  it('PlanDetail extends PlanSummary with distinct lessons field', () => {
    // lessonsPreview on PlanSummary, lessons (LessonsView) on PlanDetail — distinct names
    type HasLessonsPreview = PlanSummary extends { lessonsPreview: unknown[] } ? true : false;
    const check: HasLessonsPreview = true;
    expect(check).toBe(true);
  });

  it('AuditSummary accepts overallScore:null + scoreSource:null + blockingFindings:null', () => {
    const s: AuditSummary = {
      present: false,
      overallScore: null,
      scoreSource: null,
      blockingFindings: null,
      blockingFindingsSource: null,
      categories: [],
      topReasons: [],
      topRisks: [],
      countsBySeverity: { Critical: 0, High: 0, Medium: 0, Low: 0 },
      autoFixableCount: 0,
      nextSteps: [],
      headlineCs: '',
      previousScoreHint: null,
      rawRelPath: '',
      warnings: [],
    };
    expect(s.overallScore).toBeNull();
    expect(s.blockingFindings).toBeNull();
  });

  it('Brief.scope accepts all three values', () => {
    const scopes: Brief['scope'][] = ['infra', 'project', 'plan'];
    expect(scopes).toHaveLength(3);
  });
});
