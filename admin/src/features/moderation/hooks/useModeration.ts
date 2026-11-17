import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import {
  dismissReport,
  getReportedChat,
  listReports,
  moderateListing,
  setAccountStatus,
  type ReportFilter,
} from '../services/moderationService';

export const reportsQueryKey = ['reports'] as const;

export function useReports(filter: ReportFilter, page: number) {
  return useQuery({
    queryKey: [...reportsQueryKey, { filter, page }],
    queryFn: () => listReports({ filter, page }),
    placeholderData: keepPreviousData,
  });
}

/**
 * A reported chat, fetched only while its dialog is open ([reportId] set).
 * Each fetch is an audited view, so it isn't refetched in the background.
 */
export function useReportedChat(reportId: string | null) {
  return useQuery({
    queryKey: [...reportsQueryKey, 'chat', reportId],
    queryFn: () => getReportedChat(reportId ?? ''),
    enabled: reportId !== null,
    staleTime: Infinity,
    refetchOnWindowFocus: false,
  });
}

/** Every moderation change refreshes reports, users and the audit log. */
function useModerationMutation<TInput>(run: (input: TInput) => Promise<void>) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: run,
    onSettled: () => {
      void client.invalidateQueries({ queryKey: reportsQueryKey });
      void client.invalidateQueries({ queryKey: ['users'] });
      void client.invalidateQueries({ queryKey: ['audit'] });
      void client.invalidateQueries({ queryKey: ['overview'] });
    },
  });
}

export function useModerateListing() {
  return useModerationMutation(({ listingId, hide, note }: { listingId: string; hide: boolean; note: string }) =>
    moderateListing(listingId, hide, note),
  );
}

export function useDismissReport() {
  return useModerationMutation(({ reportId, note }: { reportId: string; note: string }) =>
    dismissReport(reportId, note),
  );
}

export function useSetAccountStatus() {
  return useModerationMutation(
    ({ userId, status, note }: { userId: string; status: 'active' | 'suspended'; note: string }) =>
      setAccountStatus(userId, status, note),
  );
}
