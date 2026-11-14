import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import type { StaffRole } from '../../auth';
import { listUsers, setStaffRole } from '../services/usersService';

export const usersQueryKey = ['users'] as const;

export function useUsers(page: number, search: string) {
  return useQuery({
    queryKey: [...usersQueryKey, { page, search }],
    queryFn: () => listUsers({ page, search }),
    placeholderData: keepPreviousData,
  });
}

export function useSetStaffRole() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ userId, role, enabled }: { userId: string; role: StaffRole; enabled: boolean }) =>
      setStaffRole(userId, role, enabled),
    onSettled: () => {
      void client.invalidateQueries({ queryKey: usersQueryKey });
      void client.invalidateQueries({ queryKey: ['overview'] });
      void client.invalidateQueries({ queryKey: ['audit'] });
    },
  });
}
