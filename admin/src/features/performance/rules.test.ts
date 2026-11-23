import { describe, expect, it } from 'vitest';

import { isPeriod, PERIODS, rangeFor } from './rules';

// Local time, like the admin's clock.
const now = new Date(2026, 10, 23, 15, 30);

describe('rangeFor', () => {
  it('counts today as one of the last 7 and 30 days', () => {
    expect(rangeFor('last_7_days', now)).toEqual({ from: new Date(2026, 10, 17).toISOString() });
    expect(rangeFor('last_30_days', now)).toEqual({ from: new Date(2026, 9, 25).toISOString() });
  });

  it('ends this month at the start of the next, across a year end', () => {
    expect(rangeFor('this_month', new Date(2026, 11, 31, 23, 59))).toEqual({
      from: new Date(2026, 11, 1).toISOString(),
      to: new Date(2027, 0, 1).toISOString(),
    });
  });

  it('has no bounds for all time', () => {
    expect(rangeFor('all_time', now)).toEqual({});
  });
});

describe('isPeriod', () => {
  it('accepts only the known periods', () => {
    for (const period of PERIODS) expect(isPeriod(period)).toBe(true);
    expect(isPeriod('yesterday')).toBe(false);
    expect(isPeriod(null)).toBe(false);
  });
});
