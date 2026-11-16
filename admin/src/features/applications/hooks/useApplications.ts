import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import type { BusinessStatus, QueueFilter, ReviewAction } from '../rules';
import {
  documentUrl,
  fetchStatusSummary,
  getApplication,
  listApplications,
  reviewApplication,
  setBusinessStatus,
} from '../services/applicationsService';

export const applicationKeys = {
  all: ['applications'] as const,
  list: (filter: QueueFilter, page: number) => [...applicationKeys.all, 'list', { filter, page }] as const,
  detail: (id: string) => [...applicationKeys.all, 'detail', id] as const,
  summary: () => [...applicationKeys.all, 'summary'] as const,
};

export function useApplications(filter: QueueFilter, page: number) {
  return useQuery({
    queryKey: applicationKeys.list(filter, page),
    queryFn: () => listApplications({ filter, page }),
    placeholderData: keepPreviousData,
  });
}

export function useApplication(id: string) {
  return useQuery({ queryKey: applicationKeys.detail(id), queryFn: () => getApplication(id) });
}

export function useStatusSummary() {
  return useQuery({ queryKey: applicationKeys.summary(), queryFn: () => fetchStatusSummary() });
}

/** Every decision refreshes the queue, the counts, the detail and the audit log. */
function useApplicationMutation<TInput>(run: (input: TInput) => Promise<void>) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: run,
    onSettled: () => {
      void client.invalidateQueries({ queryKey: applicationKeys.all });
      void client.invalidateQueries({ queryKey: ['audit'] });
    },
  });
}

export function useReviewApplication() {
  return useApplicationMutation(({ id, action, note }: { id: string; action: ReviewAction; note: string }) =>
    reviewApplication(id, action, note),
  );
}

/** Opens a private document in a new tab through a short-lived signed link. */
export function useOpenDocument() {
  return useMutation({
    mutationFn: async (path: string) => {
      const url = await documentUrl(path);
      window.open(url, '_blank', 'noopener');
    },
  });
}

export function useSetBusinessStatus() {
  return useApplicationMutation(
    ({ businessId, status, note }: { businessId: string; status: BusinessStatus; note: string }) =>
      setBusinessStatus(businessId, status, note),
  );
}
