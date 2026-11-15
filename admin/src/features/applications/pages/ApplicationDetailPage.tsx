import ArrowBackRoundedIcon from '@mui/icons-material/ArrowBackRounded';
import DescriptionOutlinedIcon from '@mui/icons-material/DescriptionOutlined';
import ImageOutlinedIcon from '@mui/icons-material/ImageOutlined';
import {
  Alert,
  Box,
  Button,
  Chip,
  Grid,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  Paper,
  Skeleton,
  Snackbar,
  Stack,
  Typography,
} from '@mui/material';
import { useState } from 'react';
import { Link as RouterLink, useParams } from 'react-router';

import { useAccess } from '../../auth';
import { messageOf } from '../../../shared/lib/errors';
import { formatDateTime } from '../../../shared/lib/format';
import { ActionDialog } from '../../../shared/ui/ActionDialog';
import { SimulatedReviewNotice } from '../components/SimulatedReviewNotice';
import { useApplication, useOpenDocument, useReviewApplication, useSetBusinessStatus } from '../hooks/useApplications';
import {
  allowedReviewActions,
  REVIEW_ACTIONS,
  STATUS_LABELS,
  STATUS_TONES,
  type BusinessStatus,
  type ReviewAction,
} from '../rules';
import { documentName, type ApplicationDetail } from '../services/applicationsService';

type Notice = { severity: 'success' | 'error'; text: string };

/** Application Detail with Decision & Notes (reviewers and admins). */
export function ApplicationDetailPage() {
  const { applicationId = '' } = useParams();
  const application = useApplication(applicationId);

  return (
    <Box>
      <Button component={RouterLink} to="/applications" startIcon={<ArrowBackRoundedIcon />} sx={{ mb: 2 }}>
        All applications
      </Button>
      {application.isPending && <Skeleton variant="rounded" height={320} />}
      {application.isError && (
        <Alert
          severity="error"
          action={
            <Button color="inherit" size="small" onClick={() => void application.refetch()}>
              Retry
            </Button>
          }
        >
          {messageOf(application.error)}
        </Alert>
      )}
      {application.data !== undefined && <Detail application={application.data} />}
    </Box>
  );
}

function Detail({ application }: { application: ApplicationDetail }) {
  const state = useAccess();
  const access = state.status === 'ready' ? state.access : null;
  const review = useReviewApplication();
  const businessStatus = useSetBusinessStatus();
  const openDocument = useOpenDocument();
  const [pending, setPending] = useState<ReviewAction | BusinessStatus | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);
  const busy = review.isPending || businessStatus.isPending;

  const ownApplication = access?.userId === application.applicantId;
  const actions = ownApplication ? [] : allowedReviewActions(application.status);
  const business = application.business;
  const applicant = application.applicant?.name ?? 'the applicant';

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
    if (pending === 'approved' || pending === 'suspended') {
      if (business === null) return;
      businessStatus.mutate(
        { businessId: business.id, status: pending, note },
        done(pending === 'suspended' ? `${business.name} is suspended.` : `${business.name} is reinstated.`),
      );
      return;
    }
    review.mutate(
      { id: application.id, action: pending, note },
      done(`Application ${STATUS_LABELS[REVIEW_ACTIONS[pending].to].toLowerCase()}.`),
    );
  };

  const dialog = pending === null ? null : dialogText(pending, application.businessName, applicant);

  return (
    <>
      <Stack direction="row" spacing={2} sx={{ alignItems: 'center', mb: 0.5, flexWrap: 'wrap' }}>
        <Typography variant="h1">{application.businessName}</Typography>
        <Chip label={STATUS_LABELS[application.status]} color={STATUS_TONES[application.status]} />
      </Stack>
      <Typography sx={{ color: 'text.secondary', mb: 3 }}>
        {application.applicant === null
          ? 'Applicant'
          : `${application.applicant.name} · ${application.applicant.email}`}
        {application.submittedAt !== null && ` · submitted ${formatDateTime(application.submittedAt)}`}
      </Typography>
      <SimulatedReviewNotice />

      <Grid container spacing={3}>
        <Grid size={{ xs: 12, lg: 8 }}>
          <Paper sx={{ p: 3, mb: 3 }}>
            <Typography variant="h2" sx={{ mb: 2 }}>
              Business details
            </Typography>
            <Field label="Category" value={application.category} />
            <Field label="What they sell" value={application.description} />
            <Field label="Contact details" value={application.contactDetails} />
            <Field label="Collection" value={application.collectionDetails} />
          </Paper>

          <Paper sx={{ p: 3, mb: 3 }}>
            <Typography variant="h2" sx={{ mb: 1 }}>
              Documents
            </Typography>
            {application.documentPaths.length === 0 ? (
              <Typography sx={{ color: 'text.secondary' }}>No documents attached.</Typography>
            ) : (
              <List disablePadding>
                {application.documentPaths.map((path) => (
                  <ListItem
                    key={path}
                    divider
                    disableGutters
                    secondaryAction={
                      <Button
                        size="small"
                        disabled={openDocument.isPending}
                        onClick={() => {
                          openDocument.mutate(path, {
                            onError: (error) => {
                              setNotice({ severity: 'error', text: messageOf(error) });
                            },
                          });
                        }}
                      >
                        Open
                      </Button>
                    }
                  >
                    <ListItemIcon>
                      {path.toLowerCase().endsWith('.pdf') ? <DescriptionOutlinedIcon /> : <ImageOutlinedIcon />}
                    </ListItemIcon>
                    <ListItemText primary={documentName(path)} />
                  </ListItem>
                ))}
              </List>
            )}
          </Paper>

          <Paper sx={{ p: 3 }}>
            <Typography variant="h2" sx={{ mb: 1 }}>
              History
            </Typography>
            <List disablePadding>
              {[...application.history].reverse().map((entry) => (
                <ListItem key={entry.id} divider disableGutters alignItems="flex-start">
                  <ListItemText
                    primary={`${STATUS_LABELS[entry.from]} → ${STATUS_LABELS[entry.to]}`}
                    secondary={
                      <>
                        {`${ROLE_LABELS[entry.actorRole]} · ${formatDateTime(entry.createdAt)}`}
                        {entry.note !== null && (
                          <Typography component="span" variant="body2" sx={{ display: 'block', whiteSpace: 'pre-wrap', mt: 0.5 }}>
                            “{entry.note}”
                          </Typography>
                        )}
                      </>
                    }
                  />
                </ListItem>
              ))}
            </List>
          </Paper>
        </Grid>

        <Grid size={{ xs: 12, lg: 4 }}>
          <Paper sx={{ p: 3, mb: 3 }}>
            <Typography variant="h2" sx={{ mb: 2 }}>
              Decision
            </Typography>
            {application.remarks !== null && (
              <Alert severity="warning" icon={false} sx={{ mb: 2, whiteSpace: 'pre-wrap' }}>
                <strong>Latest reviewer note:</strong> {application.remarks}
              </Alert>
            )}
            {ownApplication && <Alert severity="info">This is your own application. Another reviewer must decide.</Alert>}
            {!ownApplication && actions.length === 0 && (
              <Typography sx={{ color: 'text.secondary' }}>{waitingText(application)}</Typography>
            )}
            <Stack spacing={1.5}>
              {actions.map((action) => (
                <Button
                  key={action}
                  variant={action === 'approve' || action === 'start_review' ? 'contained' : 'outlined'}
                  color={action === 'reject' ? 'error' : action === 'approve' ? 'success' : 'primary'}
                  disabled={busy}
                  onClick={() => {
                    setPending(action);
                  }}
                >
                  {REVIEW_ACTIONS[action].label}
                </Button>
              ))}
            </Stack>
          </Paper>

          {business !== null && (
            <Paper sx={{ p: 3 }}>
              <Typography variant="h2" sx={{ mb: 1 }}>
                Business
              </Typography>
              <Stack direction="row" spacing={1} sx={{ alignItems: 'center', mb: 2 }}>
                <Typography sx={{ fontWeight: 600 }}>{business.name}</Typography>
                <Chip
                  size="small"
                  label={business.status === 'approved' ? 'Active' : 'Suspended'}
                  color={business.status === 'approved' ? 'success' : 'error'}
                />
              </Stack>
              {access?.isAdmin === true && (
                <Button
                  fullWidth
                  variant="outlined"
                  color={business.status === 'approved' ? 'error' : 'primary'}
                  disabled={busy}
                  onClick={() => {
                    setPending(business.status === 'approved' ? 'suspended' : 'approved');
                  }}
                >
                  {business.status === 'approved' ? 'Suspend business' : 'Reinstate business'}
                </Button>
              )}
            </Paper>
          )}
        </Grid>
      </Grid>

      {dialog !== null && (
        <ActionDialog
          open
          title={dialog.title}
          message={dialog.message}
          confirmLabel={dialog.confirm}
          danger={dialog.danger}
          noteRequired={dialog.noteRequired}
          noteMaxLength={dialog.noteMaxLength}
          noteHelp={dialog.noteHelp}
          notice={dialog.final ? <SimulatedReviewNotice /> : undefined}
          busy={busy}
          onCancel={() => {
            setPending(null);
          }}
          onConfirm={confirm}
        />
      )}

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
    </>
  );
}

const ROLE_LABELS = { applicant: 'Applicant', reviewer: 'Reviewer', admin: 'Admin' } as const;

function Field({ label, value }: { label: string; value: string }) {
  return (
    <Box sx={{ mb: 2 }}>
      <Typography variant="body2" sx={{ color: 'text.secondary' }}>
        {label}
      </Typography>
      <Typography sx={{ whiteSpace: 'pre-wrap' }}>{value.length > 0 ? value : '—'}</Typography>
    </Box>
  );
}

function waitingText(application: ApplicationDetail): string {
  switch (application.status) {
    case 'info_requested':
      return 'Waiting for the applicant to make changes and resubmit.';
    case 'approved':
      return application.decidedAt === null ? 'Approved.' : `Approved ${formatDateTime(application.decidedAt)}.`;
    case 'rejected':
      return application.decidedAt === null ? 'Rejected.' : `Rejected ${formatDateTime(application.decidedAt)}.`;
    default:
      return 'No action needed.';
  }
}

type DialogText = {
  title: string;
  message: string;
  confirm: string;
  danger: boolean;
  noteRequired: boolean;
  noteMaxLength: number;
  noteHelp: string;
  final: boolean;
};

function dialogText(pending: ReviewAction | BusinessStatus, business: string, applicant: string): DialogText {
  const toApplicant = 'The applicant sees this note. It is also kept in the history and audit log.';
  switch (pending) {
    case 'start_review':
      return {
        title: 'Start the review?',
        message: `${applicant} is told that "${business}" is under review. You can then approve it, request changes or reject it.`,
        confirm: 'Start review',
        danger: false,
        noteRequired: false,
        noteMaxLength: 1000,
        noteHelp: toApplicant,
        final: false,
      };
    case 'request_info':
      return {
        title: 'Request changes?',
        message: `"${business}" goes back to ${applicant} to edit and resubmit. Say exactly what to change.`,
        confirm: 'Request changes',
        danger: false,
        noteRequired: true,
        noteMaxLength: 1000,
        noteHelp: toApplicant,
        final: false,
      };
    case 'approve':
      return {
        title: `Approve "${business}"?`,
        message: `This creates the business for ${applicant} and turns on business features immediately. Approval is final.`,
        confirm: 'Approve',
        danger: false,
        noteRequired: false,
        noteMaxLength: 1000,
        noteHelp: toApplicant,
        final: true,
      };
    case 'reject':
      return {
        title: `Reject "${business}"?`,
        message: `Rejection is final. ${applicant} sees your reason and may start a new application.`,
        confirm: 'Reject',
        danger: true,
        noteRequired: true,
        noteMaxLength: 1000,
        noteHelp: toApplicant,
        final: true,
      };
    case 'suspended':
      return {
        title: `Suspend "${business}"?`,
        message: 'The owner loses business features at once and is notified. You can reinstate it later.',
        confirm: 'Suspend',
        danger: true,
        noteRequired: false,
        noteMaxLength: 500,
        noteHelp: 'The owner sees this note. It is also saved in the audit log.',
        final: false,
      };
    case 'approved':
      return {
        title: `Reinstate "${business}"?`,
        message: 'The owner gets business features back at once and is notified.',
        confirm: 'Reinstate',
        danger: false,
        noteRequired: false,
        noteMaxLength: 500,
        noteHelp: 'The owner sees this note. It is also saved in the audit log.',
        final: false,
      };
  }
}
