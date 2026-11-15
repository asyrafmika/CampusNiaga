-- CampusNiaga Phase 2 (M1): reports and admin moderation.
-- See docs/data-dictionary.md ("reports") and docs/api-contracts.md.
--
-- Students report listings through report_listing(). Admins act through
-- moderate_listing(), dismiss_report() and set_account_status(); every admin
-- action writes an audit entry in the same transaction. Reports are never
-- deleted, so the history stays available for audit.

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  listing_id uuid references public.listings (id) on delete set null,
  reported_user_id uuid references public.profiles (id) on delete set null,
  reason text not null check (reason in ('prohibited_item', 'scam', 'offensive', 'misleading', 'other')),
  details text not null default '' check (char_length(details) <= 500),
  status text not null default 'open' check (status in ('open', 'reviewed', 'actioned')),
  action text check (action in ('dismissed', 'listing_hidden', 'account_suspended')),
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  review_note text check (review_note is null or char_length(review_note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- An open report has no outcome yet; a closed one has.
  check ((status = 'open') = (action is null))
);

create trigger reports_set_updated_at
  before update on public.reports
  for each row execute function public.set_updated_at();

-- One open report per student per listing.
create unique index reports_one_open_per_reporter
  on public.reports (reporter_id, listing_id)
  where status = 'open';
create index reports_status_idx on public.reports (status, created_at desc);
create index reports_listing_idx on public.reports (listing_id);

------------------------------------------------------------------------------
-- Students
------------------------------------------------------------------------------

create function public.report_listing(listing_id uuid, reason text, details text default '')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_details text := btrim(coalesce(report_listing.details, ''));
  listing public.listings;
  new_id uuid;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if report_listing.reason is null
     or report_listing.reason not in ('prohibited_item', 'scam', 'offensive', 'misleading', 'other') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose a reason.');
  end if;
  if char_length(v_details) > 500 then
    perform public.raise_app_error('INVALID_INPUT', 'Details can be up to 500 characters.');
  end if;
  if report_listing.reason = 'other' and v_details = '' then
    perform public.raise_app_error('INVALID_INPUT', 'Tell us what''s wrong.');
  end if;

  select * into listing from public.listings as l where l.id = report_listing.listing_id;
  if not found or listing.status = 'draft' then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
  if listing.owner_id = uid then
    perform public.raise_app_error('FORBIDDEN', 'You can''t report your own listing.');
  end if;
  if exists (select 1 from public.reports as r
             where r.reporter_id = uid and r.listing_id = listing.id and r.status = 'open') then
    perform public.raise_app_error('ALREADY_EXISTS', 'You''ve already reported this listing.');
  end if;
  if (select count(*) from public.reports as r
      where r.reporter_id = uid and r.created_at > now() - interval '1 day') >= 10 then
    perform public.raise_app_error('RATE_LIMITED', 'You''ve sent a lot of reports today. Try again tomorrow.');
  end if;

  insert into public.reports (reporter_id, listing_id, reported_user_id, reason, details)
  values (uid, listing.id, listing.owner_id, report_listing.reason, v_details)
  returning id into new_id;

  return jsonb_build_object('report_id', new_id, 'status', 'open');
end;
$$;

------------------------------------------------------------------------------
-- Admins
------------------------------------------------------------------------------

-- Hides a listing from everyone but its owner and admins, or restores it.
-- Hiding closes the listing's open reports as actioned.
create function public.moderate_listing(listing_id uuid, hide boolean, note text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_note text := nullif(btrim(coalesce(moderate_listing.note, '')), '');
  listing public.listings;
  changed boolean;
begin
  if not public.is_admin() then
    perform public.raise_app_error('FORBIDDEN', 'Administrator access required.');
  end if;
  if hide is null or char_length(v_note) > 500 then
    perform public.raise_app_error('INVALID_INPUT', 'Say whether to hide or restore, with a note of up to 500 characters.');
  end if;

  select * into listing from public.listings as l where l.id = moderate_listing.listing_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;

  changed := listing.hidden is distinct from hide;
  if changed then
    update public.listings as l set hidden = hide where l.id = listing.id;
    insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
    values (uid, case when hide then 'listing.hidden' else 'listing.restored' end,
            'listing', listing.id::text, jsonb_build_object('note', v_note, 'title', listing.title));
    perform public.notify(listing.owner_id,
      case when hide then 'listing_hidden' else 'listing_restored' end,
      case when hide then 'Listing hidden by an administrator' else 'Listing restored' end,
      coalesce(v_note, listing.title), 'listing:' || listing.id);
  end if;

  if hide then
    update public.reports as r
    set status = 'actioned', action = 'listing_hidden', reviewed_by = uid, reviewed_at = now(), review_note = v_note
    where r.listing_id = listing.id and r.status = 'open';
  end if;

  return jsonb_build_object('listing_id', listing.id, 'hidden', hide, 'changed', changed);
end;
$$;

-- Closes a report without action.
create function public.dismiss_report(report_id uuid, note text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_note text := nullif(btrim(coalesce(dismiss_report.note, '')), '');
  report public.reports;
begin
  if not public.is_admin() then
    perform public.raise_app_error('FORBIDDEN', 'Administrator access required.');
  end if;
  if char_length(v_note) > 500 then
    perform public.raise_app_error('INVALID_INPUT', 'The note can be up to 500 characters.');
  end if;

  select * into report from public.reports as r where r.id = dismiss_report.report_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Report not found.');
  end if;
  if report.status <> 'open' then
    perform public.raise_app_error('INVALID_TRANSITION', 'This report is already closed.');
  end if;

  update public.reports as r
  set status = 'reviewed', action = 'dismissed', reviewed_by = uid, reviewed_at = now(), review_note = v_note
  where r.id = report.id;

  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values (uid, 'report.dismissed', 'report', report.id::text, jsonb_build_object('note', v_note));

  return jsonb_build_object('report_id', report.id, 'status', 'reviewed');
end;
$$;

-- Suspends or reactivates an account. A suspended account fails is_student(),
-- so it can't trade, and its listings leave the feed. Suspending closes the
-- open reports about that user as actioned.
create function public.set_account_status(user_id uuid, account_status text, note text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_note text := nullif(btrim(coalesce(set_account_status.note, '')), '');
  current_status text;
  changed boolean;
begin
  if not public.is_admin() then
    perform public.raise_app_error('FORBIDDEN', 'Administrator access required.');
  end if;
  if set_account_status.account_status is null
     or set_account_status.account_status not in ('active', 'suspended')
     or char_length(v_note) > 500 then
    perform public.raise_app_error('INVALID_INPUT', 'Choose active or suspended, with a note of up to 500 characters.');
  end if;
  if set_account_status.user_id = uid then
    perform public.raise_app_error('FORBIDDEN', 'You can''t change your own account status.');
  end if;

  select p.account_status into current_status from public.profiles as p where p.id = set_account_status.user_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'User not found.');
  end if;

  changed := current_status <> set_account_status.account_status;
  if changed then
    update public.profiles as p set account_status = set_account_status.account_status
    where p.id = set_account_status.user_id;
    insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
    values (uid,
            case when set_account_status.account_status = 'suspended' then 'account.suspended' else 'account.reactivated' end,
            'user', set_account_status.user_id::text, jsonb_build_object('note', v_note));
  end if;

  if set_account_status.account_status = 'suspended' then
    update public.reports as r
    set status = 'actioned', action = 'account_suspended', reviewed_by = uid, reviewed_at = now(), review_note = v_note
    where r.reported_user_id = set_account_status.user_id and r.status = 'open';
  end if;

  return jsonb_build_object('user_id', set_account_status.user_id,
                            'account_status', set_account_status.account_status, 'changed', changed);
end;
$$;

------------------------------------------------------------------------------
-- Row Level Security and privileges
------------------------------------------------------------------------------

alter table public.reports enable row level security;

revoke all on public.reports from anon, authenticated;
grant select on public.reports to authenticated;

create policy "Reporters see their own reports; admins see all"
  on public.reports for select to authenticated
  using (reporter_id = (select auth.uid()) or (select public.is_admin()));

revoke execute on function
  public.report_listing(uuid, text, text),
  public.moderate_listing(uuid, boolean, text),
  public.dismiss_report(uuid, text),
  public.set_account_status(uuid, text, text)
from public, anon;

grant execute on function
  public.report_listing(uuid, text, text),
  public.moderate_listing(uuid, boolean, text),
  public.dismiss_report(uuid, text),
  public.set_account_status(uuid, text, text)
to authenticated;
