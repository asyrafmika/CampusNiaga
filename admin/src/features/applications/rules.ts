/**
 * Business application rules (M2), mirroring the state machine in
 * docs/data-dictionary.md. The database enforces them in
 * `review_business_application`; this decides which buttons to show.
 */

export const APPLICATION_STATUSES = [
  'draft',
  'submitted',
  'under_review',
  'info_requested',
  'approved',
  'rejected',
] as const;

export type ApplicationStatus = (typeof APPLICATION_STATUSES)[number];

/** Statuses staff can see (drafts are private to the applicant). */
export type ReviewableStatus = Exclude<ApplicationStatus, 'draft'>;

export const STATUS_LABELS: Record<ApplicationStatus, string> = {
  draft: 'Draft',
  submitted: 'Submitted',
  under_review: 'Under review',
  info_requested: 'Changes requested',
  approved: 'Approved',
  rejected: 'Rejected',
};

export type StatusTone = 'default' | 'info' | 'warning' | 'success' | 'error';

export const STATUS_TONES: Record<ApplicationStatus, StatusTone> = {
  draft: 'default',
  submitted: 'info',
  under_review: 'info',
  info_requested: 'warning',
  approved: 'success',
  rejected: 'error',
};

export function isApplicationStatus(value: string): value is ApplicationStatus {
  return (APPLICATION_STATUSES as readonly string[]).includes(value);
}

/** Throws on a status the dashboard doesn't know, rather than guessing. */
export function applicationStatusOf(value: string): ApplicationStatus {
  if (isApplicationStatus(value)) return value;
  throw new Error(`Unknown application status: ${value}`);
}

export type ReviewAction = 'start_review' | 'request_info' | 'approve' | 'reject';

type ActionInfo = {
  label: string;
  /** The status the application moves to. */
  to: ReviewableStatus;
  /** The applicant must be told why. */
  needsNote: boolean;
  /** Approving and rejecting are final. */
  final: boolean;
};

export const REVIEW_ACTIONS: Record<ReviewAction, ActionInfo> = {
  start_review: { label: 'Start review', to: 'under_review', needsNote: false, final: false },
  request_info: { label: 'Request changes', to: 'info_requested', needsNote: true, final: false },
  approve: { label: 'Approve', to: 'approved', needsNote: false, final: true },
  reject: { label: 'Reject', to: 'rejected', needsNote: true, final: true },
};

/** The reviewer actions allowed from [status], in the order they are shown. */
export function allowedReviewActions(status: ApplicationStatus): ReviewAction[] {
  switch (status) {
    case 'submitted':
      return ['start_review'];
    case 'under_review':
      return ['approve', 'request_info', 'reject'];
    case 'draft':
    case 'info_requested':
    case 'approved':
    case 'rejected':
      return [];
  }
}

/** Queue tabs: what needs a reviewer, then each later status, then all. */
export const QUEUE_FILTERS = ['needs_review', 'info_requested', 'approved', 'rejected', 'all'] as const;

export type QueueFilter = (typeof QUEUE_FILTERS)[number];

export const QUEUE_FILTER_LABELS: Record<QueueFilter, string> = {
  needs_review: 'Needs review',
  info_requested: 'Changes requested',
  approved: 'Approved',
  rejected: 'Rejected',
  all: 'All',
};

/** The statuses a queue tab shows. */
export function statusesFor(filter: QueueFilter): ReviewableStatus[] {
  switch (filter) {
    case 'needs_review':
      return ['submitted', 'under_review'];
    case 'all':
      return ['submitted', 'under_review', 'info_requested', 'approved', 'rejected'];
    default:
      return [filter];
  }
}

export type BusinessStatus = 'approved' | 'suspended';

export function businessStatusOf(value: string): BusinessStatus {
  if (value === 'approved' || value === 'suspended') return value;
  throw new Error(`Unknown business status: ${value}`);
}
