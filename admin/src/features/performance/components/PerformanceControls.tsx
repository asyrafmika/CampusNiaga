import { Alert, Tab, Tabs } from '@mui/material';

import { PERIOD_LABELS, PERIODS, type Period } from '../rules';

/** The figures' limits, shown on both performance pages. */
export function EstimatedFiguresNotice() {
  return (
    <Alert severity="info" variant="outlined" sx={{ mb: 3 }}>
      Estimated (self-reported). Revenue adds up the orders each seller marked completed; CampusNiaga doesn&apos;t
      verify payments, and sales outside the app aren&apos;t counted, so these are not an official assessment. Costs
      and profit are private to the seller. Every view is recorded in the audit log.
    </Alert>
  );
}

type PeriodTabsProps = {
  value: Period;
  onChange: (period: Period) => void;
};

export function PeriodTabs({ value, onChange }: PeriodTabsProps) {
  return (
    <Tabs
      value={value}
      onChange={(_e, next: Period) => {
        onChange(next);
      }}
      variant="scrollable"
      aria-label="Period"
      sx={{ mb: 3 }}
    >
      {PERIODS.map((period) => (
        <Tab key={period} label={PERIOD_LABELS[period]} value={period} />
      ))}
    </Tabs>
  );
}
