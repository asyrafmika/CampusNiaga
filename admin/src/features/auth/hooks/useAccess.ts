import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';

import type { StaffAccess } from '../access';
import { fetchAccess, onSessionChange } from '../services/authService';

export type Session = { status: 'loading' } | { status: 'signedOut' } | { status: 'signedIn'; userId: string };

/** The current Supabase session, kept up to date. */
export function useSession(): Session {
  const [session, setSession] = useState<Session>({ status: 'loading' });
  useEffect(
    () =>
      onSessionChange((userId) => {
        setSession(userId === null ? { status: 'signedOut' } : { status: 'signedIn', userId });
      }),
    [],
  );
  return session;
}

export type AccessState =
  | { status: 'loading' }
  | { status: 'signedOut' }
  | { status: 'error'; error: Error; retry: () => void }
  | { status: 'ready'; access: StaffAccess };

export const accessQueryKey = (userId: string) => ['access', userId] as const;

/** Who is signed in and what they may do. Roles are read live from the database. */
export function useAccess(): AccessState {
  const session = useSession();
  const userId = session.status === 'signedIn' ? session.userId : null;
  const query = useQuery({
    queryKey: accessQueryKey(userId ?? ''),
    queryFn: fetchAccess,
    enabled: userId !== null,
  });

  if (session.status === 'loading') return { status: 'loading' };
  if (session.status === 'signedOut') return { status: 'signedOut' };
  if (query.isError) return { status: 'error', error: query.error, retry: () => void query.refetch() };
  if (query.data === undefined) return { status: 'loading' };
  return { status: 'ready', access: query.data };
}
