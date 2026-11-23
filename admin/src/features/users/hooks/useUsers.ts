import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { listUsers, setAdminRole } from '../services/usersService';

export const usersQueryKey = ['users'] as const;

export function useUsers(page: number, search: string) {
  return useQuery({
    queryKey: [...usersQueryKey, { page, search }],
    queryFn: () => listUsers({ page, search }),
    placeholderData: keepPreviousData,
  });
}

export function useSetAdminRole() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ userId, enabled }: { userId: string; enabled: boolean }) => setAdminRole(userId, enabled),
    onSettled: () => {
      void client.invalidateQueries({ queryKey: usersQueryKey });
      void client.invalidateQueries({ queryKey: ['overview'] });
      void client.invalidateQueries({ queryKey: ['audit'] });
    },
  });
}
