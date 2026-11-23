import {
  Alert,
  Box,
  Button,
  Chip,
  Paper,
  Tab,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TablePagination,
  TableRow,
  Tabs,
  Typography,
} from '@mui/material';
import { useState } from 'react';
import { useNavigate } from 'react-router';

import { messageOf } from '../../../shared/lib/errors';
import { formatDateTime, PAGE_SIZE } from '../../../shared/lib/format';
import { SimulatedReviewNotice } from '../components/SimulatedReviewNotice';
import { StatusSummary } from '../components/StatusSummary';
import { useApplications } from '../hooks/useApplications';
import { QUEUE_FILTER_LABELS, QUEUE_FILTERS, STATUS_LABELS, STATUS_TONES, type QueueFilter } from '../rules';

/** Applications Queue (HDC administrators): oldest submission first. */
export function ApplicationsPage() {
  const [filter, setFilter] = useState<QueueFilter>('needs_review');
  const [page, setPage] = useState(0);
  const applications = useApplications(filter, page);
  const navigate = useNavigate();

  return (
    <Box>
      <Typography variant="h1">Business applications</Typography>
      <Typography sx={{ color: 'text.secondary', mt: 0.5, mb: 3 }}>
        Students applying to sell as a business. Open one to review it and decide.
      </Typography>
      <SimulatedReviewNotice />

      <Box sx={{ mb: 3 }}>
        <StatusSummary />
      </Box>

      <Paper sx={{ p: 3 }}>
        <Tabs
          value={filter}
          onChange={(_e, value: QueueFilter) => {
            setFilter(value);
            setPage(0);
          }}
          variant="scrollable"
          sx={{ mb: 2 }}
        >
          {QUEUE_FILTERS.map((f) => (
            <Tab key={f} label={QUEUE_FILTER_LABELS[f]} value={f} />
          ))}
        </Tabs>

        {applications.isError && (
          <Alert
            severity="error"
            action={
              <Button color="inherit" size="small" onClick={() => void applications.refetch()}>
                Retry
              </Button>
            }
          >
            {messageOf(applications.error)}
          </Alert>
        )}

        <TableContainer>
          <Table aria-label="Applications">
            <TableHead>
              <TableRow>
                <TableCell>Business</TableCell>
                <TableCell>Applicant</TableCell>
                <TableCell>Category</TableCell>
                <TableCell>Submitted</TableCell>
                <TableCell>Status</TableCell>
                <TableCell align="right" />
              </TableRow>
            </TableHead>
            <TableBody>
              {applications.data?.rows.map((row) => (
                <TableRow
                  key={row.id}
                  hover
                  sx={{ cursor: 'pointer' }}
                  onClick={() => void navigate(`/applications/${row.id}`)}
                >
                  <TableCell sx={{ fontWeight: 600 }}>{row.businessName}</TableCell>
                  <TableCell>
                    {row.applicant?.name ?? '—'}
                    <Typography variant="body2" sx={{ color: 'text.secondary' }}>
                      {row.applicant?.email}
                    </Typography>
                  </TableCell>
                  <TableCell>{row.category}</TableCell>
                  <TableCell>{row.submittedAt === null ? '—' : formatDateTime(row.submittedAt)}</TableCell>
                  <TableCell>
                    <Chip label={STATUS_LABELS[row.status]} color={STATUS_TONES[row.status]} size="small" />
                  </TableCell>
                  <TableCell align="right">
                    <Button size="small">Open</Button>
                  </TableCell>
                </TableRow>
              ))}
              {applications.isLoading && (
                <TableRow>
                  <TableCell colSpan={6} align="center" sx={{ color: 'text.secondary', py: 4 }}>
                    Loading applications…
                  </TableCell>
                </TableRow>
              )}
              {applications.data?.rows.length === 0 && (
                <TableRow>
                  <TableCell colSpan={6} align="center" sx={{ color: 'text.secondary', py: 4 }}>
                    {filter === 'needs_review' ? 'Nothing waiting for review. All caught up!' : 'No applications here.'}
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </TableContainer>

        <TablePagination
          component="div"
          count={applications.data?.total ?? 0}
          page={page}
          rowsPerPage={PAGE_SIZE}
          rowsPerPageOptions={[PAGE_SIZE]}
          onPageChange={(_e, next) => {
            setPage(next);
          }}
        />
      </Paper>
    </Box>
  );
}
