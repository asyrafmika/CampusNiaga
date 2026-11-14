import {
  Alert,
  Box,
  Chip,
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
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { useState } from 'react';

import { messageOf } from '../../../shared/lib/errors';
import { formatDateTime, PAGE_SIZE } from '../../../shared/lib/format';
import { ACTION_LABELS, listAuditLogs } from '../services/auditService';

export function AuditLogPage() {
  const [page, setPage] = useState(0);
  const logs = useQuery({
    queryKey: ['audit', { page }],
    queryFn: () => listAuditLogs({ page }),
    placeholderData: keepPreviousData,
  });

  return (
    <Box>
      <Typography variant="h1">Audit Log</Typography>
      <Typography sx={{ color: 'text.secondary', mt: 0.5, mb: 3 }}>
        Every privileged change, newest first. Entries cannot be edited or deleted.
      </Typography>

      <Paper sx={{ p: 3 }}>
        {logs.isError && <Alert severity="error">{messageOf(logs.error)}</Alert>}
        <TableContainer>
          <Table aria-label="Audit log">
            <TableHead>
              <TableRow>
                <TableCell>When</TableCell>
                <TableCell>Action</TableCell>
                <TableCell>By</TableCell>
                <TableCell>Target</TableCell>
                <TableCell>Details</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {logs.data?.rows.map((row) => (
                <TableRow key={row.id} hover>
                  <TableCell>{formatDateTime(row.createdAt)}</TableCell>
                  <TableCell>
                    <Chip label={ACTION_LABELS[row.action] ?? row.action} size="small" />
                  </TableCell>
                  <TableCell>{row.actorEmail ?? 'System'}</TableCell>
                  <TableCell>{row.targetLabel}</TableCell>
                  <TableCell sx={{ color: 'text.secondary' }}>{row.details}</TableCell>
                </TableRow>
              ))}
              {logs.data?.rows.length === 0 && (
                <TableRow>
                  <TableCell colSpan={5} align="center" sx={{ color: 'text.secondary', py: 4 }}>
                    Nothing recorded yet.
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </TableContainer>
        <TablePagination
          component="div"
          count={logs.data?.total ?? 0}
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
