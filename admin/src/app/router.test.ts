import { describe, expect, it } from 'vitest';

import { routerBasename } from './router';

describe('routerBasename', () => {
  it('keeps the root when the dashboard is served from /', () => {
    expect(routerBasename('/')).toBe('/');
  });

  it('drops the trailing slash of a GitHub Pages sub-path', () => {
    expect(routerBasename('/CampusNiaga/')).toBe('/CampusNiaga');
  });
});
