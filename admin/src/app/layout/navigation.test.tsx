import { describe, expect, it } from 'vitest';

import { NAV_ITEMS } from './navigation';

describe('NAV_ITEMS', () => {
  it('lists every page for the HDC administrator', () => {
    expect(NAV_ITEMS.map((i) => i.label)).toEqual([
      'Overview',
      'Applications',
      'Business Performance',
      'Reports & Moderation',
      'Users & Roles',
      'Audit Log',
    ]);
  });

  it('has no pages waiting for a later phase', () => {
    expect(NAV_ITEMS.filter((i) => i.comingIn !== undefined)).toEqual([]);
  });
});
