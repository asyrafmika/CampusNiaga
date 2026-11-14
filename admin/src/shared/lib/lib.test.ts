import { describe, expect, it } from 'vitest';

import { AppError, toAppError } from './errors';
import { escapeLike } from './format';

describe('toAppError', () => {
  it('keeps the database message for a reason it explains', () => {
    const error = toAppError({
      code: 'P0001',
      details: 'FORBIDDEN',
      message: "You can't remove your own administrator role.",
    });
    expect(error).toBeInstanceOf(AppError);
    expect(error.reason).toBe('FORBIDDEN');
    expect(error.message).toBe("You can't remove your own administrator role.");
  });

  it('treats a missing privilege as forbidden', () => {
    const error = toAppError({ code: '42501', details: null, message: 'permission denied for table audit_logs' });
    expect(error.reason).toBe('FORBIDDEN');
    expect(error.message).toBe('You do not have permission to do that.');
  });

  it('hides unexpected database errors behind a generic message', () => {
    const error = toAppError({ code: 'XX000', details: null, message: 'internal error at line 4' });
    expect(error.message).toBe('Something went wrong. Please try again.');
    expect(error.reason).toBeUndefined();
  });
});

describe('escapeLike', () => {
  it('matches %, _ and \\ literally', () => {
    expect(escapeLike('50%_off\\')).toBe('50\\%\\_off\\\\');
  });

  it('leaves ordinary text alone', () => {
    expect(escapeLike('ali@student.usm.my')).toBe('ali@student.usm.my');
  });
});
