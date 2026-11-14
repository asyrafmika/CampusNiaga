import { describe, expect, it } from 'vitest';

import { visibleNavItems } from './navigation';

const access = { userId: 'u1', email: 'a@usm.my', isReviewer: false, isAdmin: false };

describe('visibleNavItems', () => {
  it('shows a reviewer only reviewer pages', () => {
    const labels = visibleNavItems({ ...access, isReviewer: true }).map((i) => i.label);
    expect(labels).toEqual(['Overview', 'Applications']);
  });

  it('shows an admin every page', () => {
    const labels = visibleNavItems({ ...access, isAdmin: true }).map((i) => i.label);
    expect(labels).toEqual(['Overview', 'Applications', 'Reports & Moderation', 'Users & Roles', 'Audit Log']);
  });

  it('marks pages from later phases', () => {
    const later = visibleNavItems({ ...access, isAdmin: true }).filter((i) => i.comingIn !== undefined);
    expect(later.map((i) => [i.label, i.comingIn])).toEqual([
      ['Applications', 'Phase 3'],
      ['Reports & Moderation', 'Phase 2'],
    ]);
  });
});
