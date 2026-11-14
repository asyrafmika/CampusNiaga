import AdminPanelSettingsOutlinedIcon from '@mui/icons-material/AdminPanelSettingsOutlined';
import AssignmentOutlinedIcon from '@mui/icons-material/AssignmentOutlined';
import GroupOutlinedIcon from '@mui/icons-material/GroupOutlined';
import HistoryOutlinedIcon from '@mui/icons-material/HistoryOutlined';
import RateReviewOutlinedIcon from '@mui/icons-material/RateReviewOutlined';
import { Alert, Box, Chip, Grid, List, ListItem, ListItemText, Paper, Skeleton, Typography } from '@mui/material';
import { useQuery } from '@tanstack/react-query';

import { useAccess } from '../../auth';
import { messageOf } from '../../../shared/lib/errors';
import { formatDateTime } from '../../../shared/lib/format';
import { StatTile } from '../../../shared/ui/StatTile';
import { ACTION_LABELS, listAuditLogs } from '../../audit/services/auditService';
import { fetchOverviewStats } from '../services/overviewService';

function AdminOverview() {
  const stats = useQuery({ queryKey: ['overview', 'stats'], queryFn: () => fetchOverviewStats() });
  const recent = useQuery({ queryKey: ['audit', 'recent'], queryFn: () => listAuditLogs({ page: 0, limit: 5 }) });

  const value = (n: number | undefined) => (n === undefined ? '…' : n.toLocaleString('en-MY'));

  return (
    <>
      {stats.isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {messageOf(stats.error)}
        </Alert>
      )}
      <Paper sx={{ p: 3, mb: 3 }}>
        <Typography variant="h2" sx={{ mb: 0.5 }}>
          Platform summary
        </Typography>
        <Typography sx={{ color: 'text.secondary', mb: 3 }}>
          Accounts and staff right now.
        </Typography>
        <Grid container spacing={2.5}>
          <Grid size={{ xs: 12, sm: 6, lg: 3 }}>
            <StatTile colour="pink" icon={<GroupOutlinedIcon fontSize="small" />} value={value(stats.data?.accounts)} label="Accounts" />
          </Grid>
          <Grid size={{ xs: 12, sm: 6, lg: 3 }}>
            <StatTile colour="orange" icon={<RateReviewOutlinedIcon fontSize="small" />} value={value(stats.data?.reviewers)} label="Reviewers" />
          </Grid>
          <Grid size={{ xs: 12, sm: 6, lg: 3 }}>
            <StatTile colour="green" icon={<AdminPanelSettingsOutlinedIcon fontSize="small" />} value={value(stats.data?.admins)} label="Admins" />
          </Grid>
          <Grid size={{ xs: 12, sm: 6, lg: 3 }}>
            <StatTile
              colour="purple"
              icon={<HistoryOutlinedIcon fontSize="small" />}
              value={value(stats.data?.auditEventsThisWeek)}
              label="Audit events"
              note="Last 7 days"
            />
          </Grid>
        </Grid>
      </Paper>

      <Paper sx={{ p: 3 }}>
        <Typography variant="h2" sx={{ mb: 2 }}>
          Recent activity
        </Typography>
        {recent.isPending && <Skeleton variant="rounded" height={120} />}
        {recent.data?.rows.length === 0 && <Typography sx={{ color: 'text.secondary' }}>Nothing recorded yet.</Typography>}
        <List disablePadding>
          {recent.data?.rows.map((row) => (
            <ListItem key={row.id} divider disableGutters>
              <ListItemText
                primary={`${ACTION_LABELS[row.action] ?? row.action}: ${row.targetLabel}`}
                secondary={`${row.actorEmail ?? 'System'} · ${formatDateTime(row.createdAt)}${row.details ? ` · ${row.details}` : ''}`}
              />
            </ListItem>
          ))}
        </List>
      </Paper>
    </>
  );
}

function ReviewerOverview() {
  return (
    <Paper sx={{ p: 4, textAlign: 'center' }}>
      <AssignmentOutlinedIcon sx={{ fontSize: 48, color: 'primary.main' }} />
      <Typography variant="h2" sx={{ mt: 2 }}>
        Business applications arrive in Phase 3
      </Typography>
      <Typography sx={{ color: 'text.secondary', mt: 1 }}>
        The application queue, decisions and status summary will appear here.
      </Typography>
      <Chip label="Coming in Phase 3" sx={{ mt: 2 }} />
    </Paper>
  );
}

export function OverviewPage() {
  const state = useAccess();
  if (state.status !== 'ready') return null;
  return (
    <Box>
      <Typography variant="h1">Overview</Typography>
      <Typography sx={{ color: 'text.secondary', mt: 0.5, mb: 3 }}>
        Welcome back, {state.access.email}.
      </Typography>
      {state.access.isAdmin ? <AdminOverview /> : <ReviewerOverview />}
    </Box>
  );
}
