import AssignmentLateOutlinedIcon from '@mui/icons-material/AssignmentLateOutlined';
import CancelOutlinedIcon from '@mui/icons-material/CancelOutlined';
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutlineOutlined';
import EditNoteOutlinedIcon from '@mui/icons-material/EditNoteOutlined';
import { Alert, Button, Grid } from '@mui/material';
import type { ReactNode } from 'react';

import type { TileColour } from '../../../app/theme';
import { messageOf } from '../../../shared/lib/errors';
import { StatTile } from '../../../shared/ui/StatTile';
import { useStatusSummary } from '../hooks/useApplications';
import type { StatusCount } from '../services/applicationsService';

type Tile = { label: string; colour: TileColour; icon: ReactNode; count: (rows: StatusCount[]) => number };

const total = (rows: StatusCount[], ...statuses: StatusCount['status'][]) =>
  rows.filter((r) => statuses.includes(r.status)).reduce((sum, r) => sum + r.total, 0);

const TILES: Tile[] = [
  {
    label: 'Needs review',
    colour: 'orange',
    icon: <AssignmentLateOutlinedIcon fontSize="small" />,
    count: (rows) => total(rows, 'submitted', 'under_review'),
  },
  {
    label: 'Changes requested',
    colour: 'purple',
    icon: <EditNoteOutlinedIcon fontSize="small" />,
    count: (rows) => total(rows, 'info_requested'),
  },
  {
    label: 'Approved',
    colour: 'green',
    icon: <CheckCircleOutlineIcon fontSize="small" />,
    count: (rows) => total(rows, 'approved'),
  },
  {
    label: 'Rejected',
    colour: 'pink',
    icon: <CancelOutlinedIcon fontSize="small" />,
    count: (rows) => total(rows, 'rejected'),
  },
];

/** Status Summary: applications per status, counted in the database. */
export function StatusSummary() {
  const summary = useStatusSummary();

  if (summary.isError) {
    return (
      <Alert
        severity="error"
        action={
          <Button color="inherit" size="small" onClick={() => void summary.refetch()}>
            Retry
          </Button>
        }
      >
        {messageOf(summary.error)}
      </Alert>
    );
  }

  return (
    <Grid container spacing={2.5}>
      {TILES.map((tile) => (
        <Grid key={tile.label} size={{ xs: 12, sm: 6, lg: 3 }}>
          <StatTile
            colour={tile.colour}
            icon={tile.icon}
            value={summary.data === undefined ? '…' : tile.count(summary.data).toLocaleString('en-MY')}
            label={tile.label}
          />
        </Grid>
      ))}
    </Grid>
  );
}
