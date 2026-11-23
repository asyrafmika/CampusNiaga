import { AppError, toAppError } from '../../../shared/lib/errors';
import { PAGE_SIZE } from '../../../shared/lib/format';
import { supabase } from '../../../shared/supabase/client';
import {
  applicationStatusOf,
  businessStatusOf,
  statusesFor,
  type ApplicationStatus,
  type BusinessStatus,
  type QueueFilter,
  type ReviewAction,
  type ReviewableStatus,
} from '../rules';

const BUCKET = 'application-documents';

/** Signed document links live this long; they are fetched on each click. */
const SIGNED_URL_SECONDS = 60;

export type Person = { name: string; email: string };

export type ApplicationRow = {
  id: string;
  businessName: string;
  category: string;
  status: ApplicationStatus;
  submittedAt: string | null;
  applicant: Person | null;
};

export type ApplicationPage = { rows: ApplicationRow[]; total: number };

export type HistoryEntry = {
  id: number;
  from: ApplicationStatus;
  to: ApplicationStatus;
  actorRole: 'applicant' | 'reviewer' | 'admin';
  note: string | null;
  createdAt: string;
};

export type BusinessSummary = { id: string; name: string; status: BusinessStatus };

export type ApplicationDetail = ApplicationRow & {
  applicantId: string;
  description: string;
  contactDetails: string;
  collectionDetails: string;
  documentPaths: string[];
  remarks: string | null;
  decidedAt: string | null;
  history: HistoryEntry[];
  business: BusinessSummary | null;
};

export type StatusCount = { status: ReviewableStatus; total: number };

function actorRoleOf(value: string): HistoryEntry['actorRole'] {
  if (value === 'applicant' || value === 'reviewer' || value === 'admin') return value;
  throw new Error(`Unknown actor role: ${value}`);
}

/**
 * One page of the review queue, oldest submission first (first come, first
 * served). Staff only; drafts are never returned (RLS).
 */
export async function listApplications({ filter, page }: { filter: QueueFilter; page: number }): Promise<ApplicationPage> {
  const { data, error, count } = await supabase
    .from('business_applications')
    .select(
      'id, business_name, category, status, submitted_at, ' +
        'applicant:profiles!business_applications_applicant_id_fkey(name, email)',
      { count: 'exact' },
    )
    .in('status', statusesFor(filter))
    .order('submitted_at', { ascending: true })
    .order('id')
    .range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1)
    .overrideTypes<
      {
        id: string;
        business_name: string;
        category: string;
        status: string;
        submitted_at: string | null;
        applicant: Person | null;
      }[],
      { merge: false }
    >();
  if (error) throw toAppError(error);

  return {
    total: count ?? data.length,
    rows: data.map((r) => ({
      id: r.id,
      businessName: r.business_name,
      category: r.category,
      status: applicationStatusOf(r.status),
      submittedAt: r.submitted_at,
      applicant: r.applicant,
    })),
  };
}

/** One application with its history and, once approved, its business. */
export async function getApplication(id: string): Promise<ApplicationDetail> {
  const [application, history, business] = await Promise.all([
    supabase
      .from('business_applications')
      .select(
        'id, applicant_id, business_name, category, description, contact_details, collection_details, ' +
          'document_paths, status, remarks, submitted_at, decided_at, ' +
          'applicant:profiles!business_applications_applicant_id_fkey(name, email)',
      )
      .eq('id', id)
      .maybeSingle()
      .overrideTypes<
        {
          id: string;
          applicant_id: string;
          business_name: string;
          category: string;
          description: string;
          contact_details: string;
          collection_details: string;
          document_paths: string[];
          status: string;
          remarks: string | null;
          submitted_at: string | null;
          decided_at: string | null;
          applicant: Person | null;
        } | null,
        { merge: false }
      >(),
    supabase
      .from('application_status_history')
      .select('id, from_status, to_status, actor_role, note, created_at')
      .eq('application_id', id)
      .order('id'),
    supabase.from('businesses').select('id, name, status').eq('application_id', id).maybeSingle(),
  ]);
  if (application.error) throw toAppError(application.error);
  if (history.error) throw toAppError(history.error);
  if (business.error) throw toAppError(business.error);

  const a = application.data;
  if (a === null) throw new AppError('That application does not exist or is still a draft.', 'NOT_FOUND');

  return {
    id: a.id,
    applicantId: a.applicant_id,
    businessName: a.business_name,
    category: a.category,
    description: a.description,
    contactDetails: a.contact_details,
    collectionDetails: a.collection_details,
    documentPaths: a.document_paths,
    status: applicationStatusOf(a.status),
    remarks: a.remarks,
    submittedAt: a.submitted_at,
    decidedAt: a.decided_at,
    applicant: a.applicant,
    history: history.data.map((h) => ({
      id: h.id,
      from: applicationStatusOf(h.from_status),
      to: applicationStatusOf(h.to_status),
      actorRole: actorRoleOf(h.actor_role),
      note: h.note,
      createdAt: h.created_at,
    })),
    business:
      business.data === null
        ? null
        : { id: business.data.id, name: business.data.name, status: businessStatusOf(business.data.status) },
  };
}

/** Counts per status from `application_status_summary` (a SQL group by). */
export async function fetchStatusSummary(): Promise<StatusCount[]> {
  const { data, error } = await supabase.rpc('application_status_summary');
  if (error) throw toAppError(error);
  return data.map((row) => {
    const status = applicationStatusOf(row.status);
    if (status === 'draft') throw new Error('Drafts are never counted.');
    return { status, total: row.total };
  });
}

/** Starts a review, requests changes, approves or rejects (audited). */
export async function reviewApplication(id: string, action: ReviewAction, note: string): Promise<void> {
  const trimmed = note.trim();
  const { error } = await supabase.rpc('review_business_application', {
    application_id: id,
    action,
    ...(trimmed.length > 0 ? { note: trimmed } : {}),
  });
  if (error) throw toAppError(error);
}

/** Suspends or reinstates a business (`set_business_status`, admins, audited). */
export async function setBusinessStatus(businessId: string, status: BusinessStatus, note: string): Promise<void> {
  const trimmed = note.trim();
  const { error } = await supabase.rpc('set_business_status', {
    business_id: businessId,
    status,
    ...(trimmed.length > 0 ? { note: trimmed } : {}),
  });
  if (error) throw toAppError(error);
}

/**
 * A short-lived link to a private document, made on demand when the
 * administrator opens it. Never stored or logged.
 */
export async function documentUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, SIGNED_URL_SECONDS);
  if (error) throw new AppError('That document could not be opened. It may have been removed.', 'NOT_FOUND');
  return data.signedUrl;
}

/** The file name to show for a stored path (`{applicant}/{application}/{stamp}_{name}`). */
export function documentName(path: string): string {
  const file = path.split('/').pop() ?? path;
  const match = /^\d+_(.+)$/.exec(file);
  return match?.[1] ?? file;
}
