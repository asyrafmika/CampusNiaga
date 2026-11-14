import { ThemeProvider } from '@mui/material';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@testing-library/react';
import type { ReactElement } from 'react';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router';

import { theme } from '../app/theme';

/**
 * Renders [ui] at [path] with the app's providers. Any other path renders a
 * marker ("page: /login?reason=…") so tests can see where a redirect went.
 */
export function renderAt(ui: ReactElement, { path = '/', at = path }: { path?: string; at?: string } = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <ThemeProvider theme={theme}>
        <MemoryRouter initialEntries={[at]}>
          <Routes>
            <Route path={path} element={ui} />
            <Route path="*" element={<RouteMarker />} />
          </Routes>
        </MemoryRouter>
      </ThemeProvider>
    </QueryClientProvider>,
  );
}

function RouteMarker() {
  const { pathname, search } = useLocation();
  return (
    <p>
      page: {pathname}
      {search}
    </p>
  );
}
