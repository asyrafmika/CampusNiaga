import { AppError, toAppError } from '../../../shared/lib/errors';
import { supabase } from '../../../shared/supabase/client';
import { parseAccess, type StaffAccess } from '../access';

const SIGN_IN_MESSAGES: Record<string, string> = {
  invalid_credentials: 'Email or password is incorrect.',
  email_not_confirmed: 'Confirm your email first, then sign in.',
  over_request_rate_limit: 'Too many attempts. Wait a minute and try again.',
};

export async function signIn(email: string, password: string): Promise<void> {
  const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
  if (error) {
    throw new AppError(
      (error.code !== undefined ? SIGN_IN_MESSAGES[error.code] : undefined) ??
        'Could not sign in. Check your connection and try again.',
    );
  }
}

export async function signOut(): Promise<void> {
  await supabase.auth.signOut();
}

export async function fetchAccess(): Promise<StaffAccess> {
  const { data, error } = await supabase.rpc('get_my_access');
  if (error) throw toAppError(error);
  return parseAccess(data);
}

/** Calls [listener] with the signed-in user's id (or null) now and on every change. */
export function onSessionChange(listener: (userId: string | null) => void): () => void {
  const { data } = supabase.auth.onAuthStateChange((_event, session) => {
    listener(session?.user.id ?? null);
  });
  return () => {
    data.subscription.unsubscribe();
  };
}
