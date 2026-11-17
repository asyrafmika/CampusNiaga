import {
  Alert,
  Box,
  Button,
  Chip,
  Paper,
  Snackbar,
  Stack,
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

import { messageOf } from '../../../shared/lib/errors';
import { formatDateTime, PAGE_SIZE } from '../../../shared/lib/format';
import { ActionDialog } from '../../../shared/ui/ActionDialog';
import { ReportedChatDialog } from '../components/ReportedChatDialog';
import { useDismissReport, useModerateListing, useReports, useSetAccountStatus } from '../hooks/useModeration';
import { REPORT_REASONS, type ReportFilter, type ReportRow } from '../services/moderationService';

type PendingAction =
  | { kind: 'hide' | 'restore'; report: ReportRow }
  | { kind: 'dismiss'; report: ReportRow }
  | { kind: 'suspend' | 'reactivate'; report: ReportRow };

const OUTCOMES: Record<string, string> = {
  dismissed: 'Dismissed',
  listing_hidden: 'Listing hidden',
  account_suspended: 'User suspended',
};

/** Reports & Moderation (admins): review reported listings and chats and act on them. */
export function ModerationPage() {
  const [filter, setFilter] = useState<ReportFilter>('open');
  const [page, setPage] = useState(0);
  const reports = useReports(filter, page);
  const moderate = useModerateListing();
  const dismiss = useDismissReport();
  const setStatus = useSetAccountStatus();
  const [pending, setPending] = useState<PendingAction | null>(null);
  const [chatReportId, setChatReportId] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ severity: 'success' | 'error'; text: string } | null>(null);
  const busy = moderate.isPending || dismiss.isPending || setStatus.isPending;

  const done = (text: string) => ({
    onSuccess: () => {
      setPending(null);
      setNotice({ severity: 'success', text });
    },
    onError: (error: unknown) => {
      setPending(null);
      setNotice({ severity: 'error', text: messageOf(error) });
    },
  });

  const confirm = (note: string) => {
    if (pending === null) return;
    const { report } = pending;
    switch (pending.kind) {
      case 'hide':
      case 'restore':
        if (report.listing === null) return;
        moderate.mutate(
          { listingId: report.listing.id, hide: pending.kind === 'hide', note },
          done(pending.kind === 'hide' ? 'Listing hidden. Its open reports are closed.' : 'Listing restored.'),
        );
        return;
      case 'dismiss':
        dismiss.mutate({ reportId: report.id, note }, done('Report dismissed.'));
        return;
      case 'suspend':
      case 'reactivate':
        if (report.seller === null) return;
        setStatus.mutate(
          { userId: report.seller.id, status: pending.kind === 'suspend' ? 'suspended' : 'active', note },
          done(pending.kind === 'suspend' ? `${report.seller.email} is suspended.` : `${report.seller.email} is active again.`),
        );
        return;
    }
  };

  const dialog = pending === null ? null : dialogText(pending);

  return (
    <Box>
      <Typography variant="h1">Reports &amp; Moderation</Typography>
      <Typography sx={{ color: 'text.secondary', mt: 0.5, mb: 3 }}>
        Listings and deal chats students reported. Hide a listing, suspend the reported user, or dismiss the report.
        Every action is recorded in the audit log.
      </Typography>

      <Paper sx={{ p: 3 }}>
        <Tabs
          value={filter}
          onChange={(_e, value: ReportFilter) => {
            setFilter(value);
            setPage(0);
          }}
          sx={{ mb: 2 }}
        >
          <Tab label="Open" value="open" />
          <Tab label="Closed" value="closed" />
        </Tabs>

        {reports.isError && (
          <Alert
            severity="error"
            action={
              <Button color="inherit" size="small" onClick={() => void reports.refetch()}>
                Retry
              </Button>
            }
          >
            {messageOf(reports.error)}
          </Alert>
        )}

        <TableContainer>
          <Table aria-label="Reports">
            <TableHead>
              <TableRow>
                <TableCell>Reported</TableCell>
                <TableCell>Reason</TableCell>
                <TableCell>Reported by</TableCell>
                <TableCell>Reported user</TableCell>
                <TableCell>When</TableCell>
                <TableCell align="right">{filter === 'open' ? 'Actions' : 'Outcome'}</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {reports.data?.rows.map((report) => (
                <ReportTableRow
                  key={report.id}
                  report={report}
                  busy={busy}
                  onAction={(kind) => {
                    setPending({ kind, report });
                  }}
                  onViewChat={() => {
                    setChatReportId(report.id);
                  }}
                />
              ))}
              {reports.isLoading && (
                <TableRow>
                  <TableCell colSpan={6} align="center" sx={{ color: 'text.secondary', py: 4 }}>
                    Loading reports…
                  </TableCell>
                </TableRow>
              )}
              {reports.data?.rows.length === 0 && (
                <TableRow>
                  <TableCell colSpan={6} align="center" sx={{ color: 'text.secondary', py: 4 }}>
                    {filter === 'open' ? 'No open reports. All clear!' : 'No closed reports yet.'}
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </TableContainer>

        <TablePagination
          component="div"
          count={reports.data?.total ?? 0}
          page={page}
          rowsPerPage={PAGE_SIZE}
          rowsPerPageOptions={[PAGE_SIZE]}
          onPageChange={(_e, next) => {
            setPage(next);
          }}
        />
      </Paper>

      {dialog !== null && (
        <ActionDialog
          open
          title={dialog.title}
          message={dialog.message}
          confirmLabel={dialog.confirm}
          danger={dialog.danger}
          noteHelp="Saved in the audit log. When a listing is hidden, its seller sees the note."
          busy={busy}
          onCancel={() => {
            setPending(null);
          }}
          onConfirm={confirm}
        />
      )}

      <ReportedChatDialog
        reportId={chatReportId}
        onClose={() => {
          setChatReportId(null);
        }}
      />

      <Snackbar
        open={notice !== null}
        autoHideDuration={4000}
        onClose={() => {
          setNotice(null);
        }}
      >
        {notice === null ? undefined : (
          <Alert severity={notice.severity} variant="filled">
            {notice.text}
          </Alert>
        )}
      </Snackbar>
    </Box>
  );
}

type ReportTableRowProps = {
  report: ReportRow;
  busy: boolean;
  onAction: (kind: PendingAction['kind']) => void;
  onViewChat: () => void;
};

function ReportTableRow({ report, busy, onAction, onViewChat }: ReportTableRowProps) {
  const { listing, seller } = report;
  const sellerSuspended = seller?.accountStatus === 'suspended';
  const chat = report.kind === 'chat';
  const who = chat ? 'user' : 'seller';
  return (
    <TableRow hover>
      <TableCell>
        {chat ? (
          <>
            <Chip label="Chat" size="small" color="info" variant="outlined" sx={{ mb: 0.5 }} />
            <Box>
              <Button size="small" onClick={onViewChat}>
                View chat
              </Button>
            </Box>
          </>
        ) : (
          <>
            <Typography sx={{ fontWeight: 600 }}>{listing?.title ?? 'Deleted listing'}</Typography>
            {listing?.hidden === true && <Chip label="Hidden" size="small" color="warning" sx={{ mt: 0.5 }} />}
          </>
        )}
      </TableCell>
      <TableCell sx={{ maxWidth: 280 }}>
        <Typography sx={{ fontWeight: 600 }}>{REPORT_REASONS[report.reason]}</Typography>
        {report.details.length > 0 && (
          <Typography variant="body2" sx={{ color: 'text.secondary', whiteSpace: 'pre-wrap' }}>
            {report.details}
          </Typography>
        )}
      </TableCell>
      <TableCell>{report.reporter?.email ?? '—'}</TableCell>
      <TableCell>
        {seller?.email ?? '—'}
        {sellerSuspended && <Chip label="Suspended" size="small" color="error" variant="outlined" sx={{ ml: 1 }} />}
      </TableCell>
      <TableCell>{formatDateTime(report.createdAt)}</TableCell>
      <TableCell align="right">
        {report.status === 'open' ? (
          <Stack direction="row" spacing={1} sx={{ justifyContent: 'flex-end' }}>
            {listing !== null && (
              <Button
                size="small"
                variant="contained"
                color="warning"
                disabled={busy}
                onClick={() => {
                  onAction(listing.hidden ? 'restore' : 'hide');
                }}
              >
                {listing.hidden ? 'Restore' : 'Hide listing'}
              </Button>
            )}
            {seller !== null && (
              <Button
                size="small"
                variant="outlined"
                color="error"
                disabled={busy}
                onClick={() => {
                  onAction(sellerSuspended ? 'reactivate' : 'suspend');
                }}
              >
                {sellerSuspended ? `Reactivate ${who}` : `Suspend ${who}`}
              </Button>
            )}
            <Button
              size="small"
              disabled={busy}
              onClick={() => {
                onAction('dismiss');
              }}
            >
              Dismiss
            </Button>
          </Stack>
        ) : (
          <Box>
            <Chip label={OUTCOMES[report.action ?? ''] ?? report.status} size="small" variant="outlined" />
            {listing?.hidden === true && (
              <Button
                size="small"
                sx={{ ml: 1 }}
                disabled={busy}
                onClick={() => {
                  onAction('restore');
                }}
              >
                Restore
              </Button>
            )}
            {report.reviewNote !== null && (
              <Typography variant="body2" sx={{ color: 'text.secondary', mt: 0.5 }}>
                {report.reviewNote}
              </Typography>
            )}
          </Box>
        )}
      </TableCell>
    </TableRow>
  );
}

function dialogText(action: PendingAction): { title: string; message: string; confirm: string; danger: boolean } {
  const title = action.report.listing?.title ?? 'this listing';
  const chat = action.report.kind === 'chat';
  const who = chat ? 'user' : 'seller';
  const seller = action.report.seller?.email ?? `this ${who}`;
  switch (action.kind) {
    case 'hide':
      return {
        title: 'Hide listing?',
        message: `"${title}" leaves the marketplace and can't be reserved. Its seller still sees it and is notified. All open reports on it are closed.`,
        confirm: 'Hide listing',
        danger: true,
      };
    case 'restore':
      return {
        title: 'Restore listing?',
        message: `"${title}" returns to the marketplace.`,
        confirm: 'Restore',
        danger: false,
      };
    case 'dismiss':
      return {
        title: 'Dismiss report?',
        message: chat
          ? 'The report is closed without action.'
          : 'The report is closed without action. The listing stays as it is.',
        confirm: 'Dismiss',
        danger: false,
      };
    case 'suspend':
      return {
        title: `Suspend ${who}?`,
        message: `${seller} can no longer buy, sell or chat, and their listings leave the marketplace. Open reports about them are closed.`,
        confirm: 'Suspend',
        danger: true,
      };
    case 'reactivate':
      return {
        title: `Reactivate ${who}?`,
        message: `${seller} can trade again.`,
        confirm: 'Reactivate',
        danger: false,
      };
  }
}
