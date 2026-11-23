import PaidOutlinedIcon from '@mui/icons-material/PaidOutlined';
import ShoppingBagOutlinedIcon from '@mui/icons-material/ShoppingBagOutlined';
import StorefrontOutlinedIcon from '@mui/icons-material/StorefrontOutlined';
import TaskAltOutlinedIcon from '@mui/icons-material/TaskAltOutlined';
import {
  Alert,
  Box,
  Button,
  Chip,
  Grid,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TablePagination,
  TableRow,
  Typography,
} from '@mui/material';
import { useState } from 'react';
import { Link as RouterLink, useSearchParams } from 'react-router';

import { messageOf } from '../../../shared/lib/errors';
import { formatRm, PAGE_SIZE } from '../../../shared/lib/format';
import { StatTile } from '../../../shared/ui/StatTile';
import { EstimatedFiguresNotice, PeriodTabs } from '../components/PerformanceControls';
import { usePerformanceList } from '../hooks/usePerformance';
import { BUSINESS_STATUS_LABELS, DEFAULT_PERIOD, isPeriod } from '../rules';
import type { PerformanceTotals } from '../services/performanceService';

function Totals({ totals }: { totals: PerformanceTotals | undefined }) {
  const count = (n: number | undefined) => (n === undefined ? '…' : n.toLocaleString('en-MY'));
  return (
    <Grid container spacing={2.5} sx={{ mb: 3 }}>
      <Grid size={{ xs: 12, sm: 6, lg: 3 }}>
        <StatTile
          colour="pink"
          icon={<StorefrontOutlinedIcon fontSize="small" />}
          value={count(totals?.businesses)}
          label="Student businesses"
          {...(totals === undefined ? {} : { note: `${totals.approvedBusinesses} approved now` })}
        />
      </Grid>
      <Grid size={{ xs: 12, sm: 6, lg: 3 }}>
        <StatTile
          colour="orange"
          icon={<ShoppingBagOutlinedIcon fontSize="small" />}
          value={count(totals?.totalOrders)}
          label="Orders placed"
        />
      </Grid>
      <Grid size={{ xs: 12, sm: 6, lg: 3 }}>
        <StatTile
          colour="green"
          icon={<TaskAltOutlinedIcon fontSize="small" />}
          value={count(totals?.completedCount)}
          label="Orders completed"
        />
      </Grid>
      <Grid size={{ xs: 12, sm: 6, lg: 3 }}>
        <StatTile
          colour="purple"
          icon={<PaidOutlinedIcon fontSize="small" />}
          value={totals === undefined ? '…' : formatRm(totals.revenueSen)}
          label="Estimated revenue"
        />
      </Grid>
    </Grid>
  );
}

/** Student entrepreneurship performance (admins): every business, highest revenue first. */
export function BusinessPerformancePage() {
  // In the URL, so a business's page opens on the same period and Back keeps it.
  const [params, setParams] = useSearchParams();
  const requested = params.get('period');
  const period = isPeriod(requested) ? requested : DEFAULT_PERIOD;
  const [page, setPage] = useState(0);
  const performance = usePerformanceList(period, page);
  const totals = performance.data?.totals;

  return (
    <Box>
      <Typography variant="h1">Business Performance</Typography>
      <Typography sx={{ color: 'text.secondary', mt: 0.5, mb: 3 }}>
        How student entrepreneurs&apos; businesses are doing. Personal Buy now sales aren&apos;t included.
      </Typography>
      <EstimatedFiguresNotice />
      <PeriodTabs
        value={period}
        onChange={(next) => {
          setPage(0);
          setParams({ period: next }, { replace: true });
        }}
      />

      {performance.isError ? (
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
      ) : (
        <>
          <Totals totals={totals} />
          <Paper sx={{ p: 3 }}>
            <TableContainer>
              <Table aria-label="Businesses">
                <TableHead>
                  <TableRow>
                    <TableCell>Business</TableCell>
                    <TableCell>Category</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell align="right">Orders</TableCell>
                    <TableCell align="right">Completed</TableCell>
                    <TableCell align="right">Estimated revenue</TableCell>
                    <TableCell align="right" />
                  </TableRow>
                </TableHead>
                <TableBody>
                  {performance.data?.rows.map((row) => (
                    <TableRow key={row.id} hover>
                      <TableCell sx={{ fontWeight: 600 }}>
                        {row.name}
                        <Typography variant="body2" sx={{ color: 'text.secondary' }}>
                          {row.ownerName}
                        </Typography>
                      </TableCell>
                      <TableCell>{row.category}</TableCell>
                      <TableCell>
                        <Chip
                          size="small"
                          color={row.status === 'approved' ? 'success' : 'error'}
                          label={BUSINESS_STATUS_LABELS[row.status]}
                        />
                      </TableCell>
                      <TableCell align="right">{row.totalOrders}</TableCell>
                      <TableCell align="right">{row.completedCount}</TableCell>
                      <TableCell align="right">{formatRm(row.revenueSen)}</TableCell>
                      <TableCell align="right">
                        <Button
                          component={RouterLink}
                          to={`/performance/${row.id}?period=${period}`}
                          size="small"
                          aria-label={`Open ${row.name}`}
                        >
                          Open
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                  {performance.isPending && (
                    <TableRow>
                      <TableCell colSpan={7} align="center" sx={{ color: 'text.secondary', py: 4 }}>
                        Loading performance…
                      </TableCell>
                    </TableRow>
                  )}
                  {performance.data?.rows.length === 0 && (
                    <TableRow>
                      <TableCell colSpan={7} align="center" sx={{ color: 'text.secondary', py: 4 }}>
                        No student businesses yet. They appear here once an application is approved.
                      </TableCell>
                    </TableRow>
                  )}
                </TableBody>
              </Table>
            </TableContainer>
            <TablePagination
              component="div"
              // Until the count arrives, enough to keep the current page in range.
              count={totals?.businesses ?? page * PAGE_SIZE + (page > 0 ? 1 : 0)}
              page={page}
              rowsPerPage={PAGE_SIZE}
              rowsPerPageOptions={[PAGE_SIZE]}
              onPageChange={(_e, next) => {
                setPage(next);
              }}
            />
          </Paper>
        </>
      )}
    </Box>
  );
}
