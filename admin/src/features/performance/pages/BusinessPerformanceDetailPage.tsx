import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import PaidOutlinedIcon from '@mui/icons-material/PaidOutlined';
import ShoppingBagOutlinedIcon from '@mui/icons-material/ShoppingBagOutlined';
import TaskAltOutlinedIcon from '@mui/icons-material/TaskAltOutlined';
import {
  Alert,
  Box,
  Button,
  Chip,
  Grid,
  Paper,
  Skeleton,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material';
import type { ReactNode } from 'react';
import { Link as RouterLink, useParams, useSearchParams } from 'react-router';

import { messageOf } from '../../../shared/lib/errors';
import { formatDateTime, formatRm } from '../../../shared/lib/format';
import { StatTile } from '../../../shared/ui/StatTile';
import { EstimatedFiguresNotice, PeriodTabs } from '../components/PerformanceControls';
import { useBusinessPerformance } from '../hooks/usePerformance';
import { BUSINESS_STATUS_LABELS, DEFAULT_PERIOD, isPeriod, ORDER_STATUS_LABELS, ORDER_STATUSES } from '../rules';
import type { BusinessPerformance } from '../services/performanceService';

type Row = { key: string; cells: ReactNode[] };

function Section({ title, head, rows, empty }: { title: string; head: string[]; rows: Row[]; empty: string }) {
  return (
    <Paper sx={{ p: 3, height: '100%', overflowX: 'auto' }}>
      <Typography variant="h2" sx={{ mb: 2 }}>
        {title}
      </Typography>
      {rows.length === 0 ? (
        <Typography sx={{ color: 'text.secondary' }}>{empty}</Typography>
      ) : (
        <Table size="small" aria-label={title}>
          <TableHead>
            <TableRow>
              {head.map((label, i) => (
                <TableCell key={label} align={i === 0 ? 'left' : 'right'}>
                  {label}
                </TableCell>
              ))}
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.map((row) => (
              <TableRow key={row.key}>
                {row.cells.map((cell, i) => (
                  <TableCell key={head[i]} align={i === 0 ? 'left' : 'right'}>
                    {cell}
                  </TableCell>
                ))}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </Paper>
  );
}

function Figures({ business }: { business: BusinessPerformance }) {
  return (
    <Grid container spacing={2.5}>
      <Grid size={{ xs: 12, sm: 4 }}>
        <StatTile
          colour="orange"
          icon={<ShoppingBagOutlinedIcon fontSize="small" />}
          value={business.totalOrders.toLocaleString('en-MY')}
          label="Orders placed"
        />
      </Grid>
      <Grid size={{ xs: 12, sm: 4 }}>
        <StatTile
          colour="green"
          icon={<TaskAltOutlinedIcon fontSize="small" />}
          value={business.completedCount.toLocaleString('en-MY')}
          label="Orders completed"
        />
      </Grid>
      <Grid size={{ xs: 12, sm: 4 }}>
        <StatTile
          colour="purple"
          icon={<PaidOutlinedIcon fontSize="small" />}
          value={formatRm(business.revenueSen)}
          label="Estimated revenue"
        />
      </Grid>
      <Grid size={{ xs: 12, md: 6 }}>
        <Section
          title="Orders by status"
          head={['Status', 'Orders']}
          rows={ORDER_STATUSES.map((s) => ({ key: s, cells: [ORDER_STATUS_LABELS[s], business.ordersByStatus[s]] }))}
          empty="No orders."
        />
      </Grid>
      <Grid size={{ xs: 12, md: 6 }}>
        <Section
          title="Best-selling products"
          head={['Product', 'Units', 'Revenue']}
          rows={business.topProducts.map((p) => ({ key: p.id, cells: [p.title, p.units, formatRm(p.revenueSen)] }))}
          empty="No completed sales in this period."
        />
      </Grid>
      <Grid size={{ xs: 12, md: 6 }}>
        <Section
          title="Stock now"
          head={['Product', 'Left']}
          rows={business.stock.map((s) => ({
            key: s.id,
            cells: [s.hidden ? `${s.title} (hidden)` : s.title, s.stock],
          }))}
          empty="No published products."
        />
      </Grid>
      <Grid size={{ xs: 12, md: 6 }}>
        <Section
          title="Pre-orders now"
          head={['Campaign', 'Places left', 'Closes']}
          rows={business.campaigns.map((c) => ({
            key: c.id,
            cells: [
              c.status === 'draft' ? `${c.title} (draft)` : c.title,
              `${c.remaining} of ${c.capacity}`,
              formatDateTime(c.closeAt),
            ],
          }))}
          empty="No draft or open pre-orders."
        />
      </Grid>
    </Grid>
  );
}

/** One student business's performance (admins). No cost or profit. */
export function BusinessPerformanceDetailPage() {
  const { businessId = '' } = useParams();
  const [params, setParams] = useSearchParams();
  const requested = params.get('period');
  const period = isPeriod(requested) ? requested : DEFAULT_PERIOD;
  const performance = useBusinessPerformance(businessId, period);
  const business = performance.data;

  return (
    <Box>
      <Button component={RouterLink} to={`/performance?period=${period}`} startIcon={<ArrowBackIcon />} sx={{ mb: 1 }}>
        All businesses
      </Button>
      <Stack direction="row" sx={{ alignItems: 'center', gap: 1.5, flexWrap: 'wrap' }}>
        <Typography variant="h1">{business?.name ?? 'Business performance'}</Typography>
        {business !== undefined && (
          <Chip
            size="small"
            color={business.status === 'approved' ? 'success' : 'error'}
            label={BUSINESS_STATUS_LABELS[business.status]}
          />
        )}
      </Stack>
      <Typography sx={{ color: 'text.secondary', mt: 0.5, mb: 3 }}>
        {business === undefined
          ? ' '
          : `${business.ownerName} · ${business.category} · Approved ${formatDateTime(business.approvedAt)}`}
      </Typography>
      <EstimatedFiguresNotice />
      <PeriodTabs
        value={period}
        onChange={(next) => {
          setParams({ period: next }, { replace: true });
        }}
      />

      {performance.isPending && <Skeleton variant="rounded" height={320} aria-label="Loading performance" />}
      {performance.isError && (
        <Alert
          severity="error"
          action={
            <Button color="inherit" size="small" onClick={() => void performance.refetch()}>
              Retry
            </Button>
          }
        >
          {messageOf(performance.error)}
        </Alert>
      )}
      {business !== undefined && <Figures business={business} />}
    </Box>
  );
}
