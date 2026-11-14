/** Reasons database functions raise (docs/api-contracts.md). */
const REASON_MESSAGES: Record<string, string> = {
  FORBIDDEN: 'You do not have permission to do that.',
  INVALID_INPUT: 'Some of the details are not valid.',
  NOT_FOUND: 'That record no longer exists.',
  INVALID_TRANSITION: 'That change is not allowed from the current status.',
  ALREADY_EXISTS: 'That already exists.',
  RATE_LIMITED: 'Too many requests. Wait a moment and try again.',
};

/** An error a service throws, with a message ready to show. */
export class AppError extends Error {
  constructor(
    message: string,
    readonly reason?: string,
  ) {
    super(message);
    this.name = 'AppError';
  }
}

interface PostgrestLikeError {
  message: string;
  details?: string | null;
  code?: string;
}

/**
 * Turns a Supabase error into an [AppError]. Known reasons get a friendly
 * message; the database's own message is kept for refusals it explains well
 * (e.g. "You can't remove your own administrator role").
 */
export function toAppError(error: PostgrestLikeError): AppError {
  const reason = error.details ?? undefined;
  if (reason !== undefined && reason in REASON_MESSAGES) {
    const useOwn = error.code === 'P0001' && error.message.length > 0;
    return new AppError(useOwn ? error.message : (REASON_MESSAGES[reason] ?? error.message), reason);
  }
  if (error.code === '42501') return new AppError(REASON_MESSAGES['FORBIDDEN'] ?? error.message, 'FORBIDDEN');
  return new AppError('Something went wrong. Please try again.');
}

export function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : 'Something went wrong. Please try again.';
}
