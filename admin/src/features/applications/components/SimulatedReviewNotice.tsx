import { Alert } from '@mui/material';

/** Shown on every application screen: this is an FYP prototype, not an official decision. */
export function SimulatedReviewNotice() {
  return (
    <Alert severity="info" variant="outlined" sx={{ mb: 3 }}>
      Prototype reviewer workflow, not an official USM/HDC decision. Approving here only enables business features in
      the CampusNiaga prototype.
    </Alert>
  );
}
