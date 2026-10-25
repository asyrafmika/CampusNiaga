import type { z } from 'zod';
import { fail } from './errors';

/**
 * Validates callable input against a zod schema.
 * Throws INVALID_INPUT listing each failing field; returns the parsed value
 * (unknown keys stripped) on success.
 */
export function parse<T extends z.ZodType>(schema: T, data: unknown): z.output<T> {
  const result = schema.safeParse(data);
  if (!result.success) {
    const problems = result.error.issues.map((issue) => {
      const field = issue.path.map(String).join('.') || '(input)';
      return `${field}: ${issue.message}`;
    });
    fail('INVALID_INPUT', problems.join('; '));
  }
  return result.data;
}
