import { useQuery } from '@tanstack/react-query';

import { rangeFor, type Period } from '../rules';
import { getBusinessPerformance, listBusinessPerformance } from '../services/performanceService';

export const performanceKeys = {
  all: ['performance'] as const,
  list: (period: Period, page: number) => [...performanceKeys.all, 'list', { period, page }] as const,
  detail: (id: string, period: Period) => [...performanceKeys.all, 'detail', { id, period }] as const,
};

// Every call is written to the audit log as a view, so fetch only when the
// admin opens a page or changes what it shows, never when the tab regains
// focus or the connection returns.
const ONLY_WHEN_ASKED = {
  staleTime: 5 * 60 * 1000,
  refetchOnWindowFocus: false,
  refetchOnReconnect: false,
} as const;

export function usePerformanceList(period: Period, page: number) {
  return useQuery({
    queryKey: performanceKeys.list(period, page),
    queryFn: () => listBusinessPerformance({ range: rangeFor(period, new Date()), page }),
    ...ONLY_WHEN_ASKED,
  });
}

export function useBusinessPerformance(id: string, period: Period) {
  return useQuery({
    queryKey: performanceKeys.detail(id, period),
    queryFn: () => getBusinessPerformance({ id, range: rangeFor(period, new Date()) }),
    ...ONLY_WHEN_ASKED,
  });
}
