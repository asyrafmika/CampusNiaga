import { isValidElement } from 'react';
import { describe, expect, it } from 'vitest';

import { RequireStaff } from '../features/auth';
import { routerBasename, routes } from './router';

describe('routes', () => {
  it('put every page behind the administrator check', () => {
    const shell = routes.find((route) => route.path === '/');
    expect(isValidElement(shell?.element) && shell.element.type).toBe(RequireStaff);
    expect(shell?.children?.map((child) => child.path ?? '(index)')).toEqual([
      '(index)',
      'applications',
      'applications/:applicationId',
      'performance',
      'performance/:businessId',
      'moderation',
      'users',
      'audit',
    ]);
  });
});

describe('routerBasename', () => {
  it('keeps the root when the dashboard is served from /', () => {
    expect(routerBasename('/')).toBe('/');
  });

  it('drops the trailing slash of a GitHub Pages sub-path', () => {
    expect(routerBasename('/CampusNiaga/')).toBe('/CampusNiaga');
  });
});
