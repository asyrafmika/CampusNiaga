import { describe, expect, it } from 'vitest';

import {
  allowedReviewActions,
  APPLICATION_STATUSES,
  applicationStatusOf,
  businessStatusOf,
  REVIEW_ACTIONS,
  statusesFor,
} from './rules';
import { documentName } from './services/applicationsService';

describe('allowedReviewActions', () => {
  it('matches the server transition table for every status', () => {
    const table = Object.fromEntries(APPLICATION_STATUSES.map((s) => [s, allowedReviewActions(s)]));
    expect(table).toEqual({
      draft: [],
      submitted: ['start_review'],
      under_review: ['approve', 'request_info', 'reject'],
      info_requested: [],
      approved: [],
      rejected: [],
    });
  });

  it('moves each action to the status the server sets', () => {
    expect(Object.fromEntries(Object.entries(REVIEW_ACTIONS).map(([a, info]) => [a, info.to]))).toEqual({
      start_review: 'under_review',
      request_info: 'info_requested',
      approve: 'approved',
      reject: 'rejected',
    });
  });

  it('requires a note exactly for requesting changes and rejecting', () => {
    const needNote = Object.entries(REVIEW_ACTIONS)
      .filter(([, info]) => info.needsNote)
      .map(([a]) => a);
    expect(needNote).toEqual(['request_info', 'reject']);
  });

  it('marks approve and reject as final', () => {
    const final = Object.entries(REVIEW_ACTIONS)
      .filter(([, info]) => info.final)
      .map(([a]) => a);
    expect(final).toEqual(['approve', 'reject']);
  });
});

describe('queue filters', () => {
  it('"Needs review" covers submitted and under review; "All" never includes drafts', () => {
    expect(statusesFor('needs_review')).toEqual(['submitted', 'under_review']);
    expect(statusesFor('all')).not.toContain('draft');
    expect(statusesFor('all')).toHaveLength(5);
    expect(statusesFor('rejected')).toEqual(['rejected']);
  });
});

describe('parsing', () => {
  it('rejects unknown statuses instead of guessing', () => {
    expect(applicationStatusOf('info_requested')).toBe('info_requested');
    expect(() => applicationStatusOf('pending')).toThrow();
    expect(businessStatusOf('suspended')).toBe('suspended');
    expect(() => businessStatusOf('closed')).toThrow();
  });

  it('shows a document by its original name', () => {
    expect(documentName('u1/a1/1731744000000_Menu_2026.pdf')).toBe('Menu_2026.pdf');
    expect(documentName('u1/a1/menu.pdf')).toBe('menu.pdf');
  });
});
