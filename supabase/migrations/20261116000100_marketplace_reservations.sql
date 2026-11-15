-- CampusNiaga Phase 2 (M1): reservations and in-app notifications.
-- See docs/data-dictionary.md ("reservations", "notifications") and
-- docs/api-contracts.md.
--
-- How units are held:
--   * A request holds its units at once: request_reservation() locks the
--     listing row (select ... for update), checks stock and takes the units
--     out in the same transaction. Two buyers asking for the last unit at the
--     same moment are serialised by that lock; the second gets ITEM_UNAVAILABLE.
--   * Declining, cancelling or expiring returns the units. Collecting keeps
--     them gone; the listing is sold when no units and no active reservations
--     remain.
--   * Expiry is lazy: stale reservations are expired whenever a reservation
--     on the same listing is requested, resolved or listed. No scheduled job.
--   * Lock order is always listing, then reservation, so two functions can't
--     deadlock on the same pair of rows.

------------------------------------------------------------------------------
-- Notifications (written by functions; the recipient may mark them read)
------------------------------------------------------------------------------

create table public.notifications (
  id bigint generated always as identity primary key,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  type text not null check (char_length(type) between 1 and 60),
  title text not null check (char_length(title) between 1 and 120),
  body text not null default '' check (char_length(body) <= 500),
  target text,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);

create function public.notify(recipient uuid, kind text, title text, body text, target text)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into public.notifications (recipient_id, type, title, body, target)
  values (recipient, kind, left(title, 120), left(body, 500), target);
$$;

------------------------------------------------------------------------------
-- Reservations
------------------------------------------------------------------------------

create table public.reservations (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  qty integer not null check (qty between 1 and 999),
  pickup_note text check (pickup_note is null or char_length(pickup_note) <= 200),
  status text not null default 'requested'
    check (status in ('requested', 'accepted', 'declined', 'cancelled', 'collected', 'expired')),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (buyer_id <> seller_id),
  -- Requested and accepted reservations always have a deadline.
  check (status not in ('requested', 'accepted') or expires_at is not null)
);

create trigger reservations_set_updated_at
  before update on public.reservations
  for each row execute function public.set_updated_at();

-- One active reservation per buyer per listing.
create unique index reservations_one_active_per_buyer
  on public.reservations (listing_id, buyer_id)
  where status in ('requested', 'accepted');
create index reservations_listing_idx on public.reservations (listing_id, status);
create index reservations_buyer_idx on public.reservations (buyer_id, created_at desc);
create index reservations_seller_idx on public.reservations (seller_id, created_at desc);

-- Expires the listing's overdue requested/accepted reservations and returns
-- their units. The caller must already hold the listing's row lock.
create function public.expire_listing_reservations(target_listing uuid)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  returned integer;
  r record;
begin
  returned := 0;
  for r in
    update public.reservations as rv
    set status = 'expired'
    where rv.listing_id = target_listing
      and rv.status in ('requested', 'accepted')
      and rv.expires_at <= now()
    returning rv.id, rv.qty, rv.buyer_id, rv.seller_id
  loop
    returned := returned + r.qty;
    perform public.notify(r.buyer_id, 'reservation_expired', 'Reservation expired',
      'A reservation of yours expired before pickup.', 'reservation:' || r.id);
  end loop;

  if returned > 0 then
    update public.listings as l
    set stock = l.stock + returned,
        status = case when l.status = 'reserved' then 'available' else l.status end
    where l.id = target_listing;
  end if;
  return returned;
end;
$$;

-- A buyer reserves `qty` units of a listing. Units are held immediately.
create function public.request_reservation(listing_id uuid, qty integer default 1, pickup_note text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  note text := nullif(btrim(coalesce(request_reservation.pickup_note, '')), '');
  listing public.listings;
  seller_active boolean;
  new_id uuid;
  deadline timestamptz := now() + interval '48 hours';
begin
  -- 1. Caller
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to reserve.');
  end if;

  -- 2. Input
  if request_reservation.qty is null or request_reservation.qty not between 1 and 999 then
    perform public.raise_app_error('INVALID_INPUT', 'Reserve between 1 and 999 units.');
  end if;
  if char_length(note) > 200 then
    perform public.raise_app_error('INVALID_INPUT', 'The pickup note can be up to 200 characters.');
  end if;
  if (select count(*) from public.reservations as rv
      where rv.buyer_id = uid and rv.created_at > now() - interval '1 hour') >= 10 then
    perform public.raise_app_error('RATE_LIMITED', 'You''ve made a lot of reservations. Try again in an hour.');
  end if;

  -- 3. Lock the listing: everything below sees a stable stock
  select * into listing from public.listings as l where l.id = request_reservation.listing_id for update;
  if not found or listing.status = 'draft' then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
  if listing.owner_id = uid then
    perform public.raise_app_error('FORBIDDEN', 'You can''t reserve your own listing.');
  end if;
  select p.account_status = 'active' into seller_active from public.profiles as p where p.id = listing.owner_id;
  if listing.hidden or not seller_active then
    perform public.raise_app_error('ITEM_UNAVAILABLE', 'This item is no longer available.');
  end if;

  -- 4. Free units held by overdue reservations, then decide
  if public.expire_listing_reservations(listing.id) > 0 then
    select * into listing from public.listings as l where l.id = listing.id;
  end if;
  if exists (select 1 from public.reservations as rv
             where rv.listing_id = listing.id and rv.buyer_id = uid and rv.status in ('requested', 'accepted')) then
    perform public.raise_app_error('ALREADY_EXISTS', 'You already have a reservation for this item.');
  end if;
  if listing.status <> 'available' or listing.stock < request_reservation.qty then
    perform public.raise_app_error('ITEM_UNAVAILABLE',
      case when listing.status = 'available' and listing.stock > 0
           then format('Only %s left.', listing.stock)
           else 'This item is no longer available.' end);
  end if;

  -- 5. Hold the units and record the request
  update public.listings as l
  set stock = l.stock - request_reservation.qty,
      status = case when l.stock - request_reservation.qty = 0 then 'reserved' else l.status end
  where l.id = listing.id;

  insert into public.reservations (listing_id, buyer_id, seller_id, qty, pickup_note, status, expires_at)
  values (listing.id, uid, listing.owner_id, request_reservation.qty, note, 'requested', deadline)
  returning id into new_id;

  perform public.notify(listing.owner_id, 'reservation_requested', 'New reservation request',
    format('Someone wants %s × %s.', request_reservation.qty, listing.title), 'reservation:' || new_id);

  return jsonb_build_object('reservation_id', new_id, 'status', 'requested', 'expires_at', deadline);
end;
$$;

-- The seller accepts, declines or marks collected; either side cancels.
create function public.resolve_reservation(reservation_id uuid, action text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  rv public.reservations;
  listing public.listings;
  new_status text;
  listing_status text;
  other uuid;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if action is null or action not in ('accept', 'decline', 'cancel', 'collect') then
    perform public.raise_app_error('INVALID_INPUT', 'Unknown action.');
  end if;

  select * into rv from public.reservations as r where r.id = resolve_reservation.reservation_id;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Reservation not found.');
  end if;
  if uid not in (rv.buyer_id, rv.seller_id) then
    perform public.raise_app_error('FORBIDDEN', 'This isn''t your reservation.');
  end if;

  -- Lock listing, then reservation; expire overdue ones; re-read.
  select * into listing from public.listings as l where l.id = rv.listing_id for update;
  perform public.expire_listing_reservations(listing.id);
  select * into rv from public.reservations as r where r.id = rv.id for update;

  if action in ('accept', 'decline', 'collect') and uid <> rv.seller_id then
    perform public.raise_app_error('FORBIDDEN', 'Only the seller can do that.');
  end if;
  if rv.status = 'expired' then
    perform public.raise_app_error('INVALID_TRANSITION', 'This reservation has expired.');
  end if;
  if (action, rv.status) not in (
    ('accept', 'requested'), ('decline', 'requested'),
    ('cancel', 'requested'), ('cancel', 'accepted'),
    ('collect', 'accepted')
  ) then
    perform public.raise_app_error('INVALID_TRANSITION',
      format('This reservation is %s, so it can''t be %s.', rv.status,
        case action when 'accept' then 'accepted' when 'decline' then 'declined'
                    when 'cancel' then 'cancelled' else 'collected' end));
  end if;

  new_status := case action when 'accept' then 'accepted' when 'decline' then 'declined'
                            when 'cancel' then 'cancelled' else 'collected' end;

  update public.reservations as r
  set status = new_status,
      -- An accepted reservation has a week for pickup.
      expires_at = case when new_status = 'accepted' then now() + interval '7 days'
                        when new_status in ('declined', 'cancelled', 'collected') then null
                        else r.expires_at end
  where r.id = rv.id;

  if new_status in ('declined', 'cancelled') then
    -- Units go back on sale.
    update public.listings as l
    set stock = l.stock + rv.qty,
        status = case when l.status = 'reserved' then 'available' else l.status end
    where l.id = listing.id;
  elsif new_status = 'collected' then
    -- Sold out once nothing is left and nobody else is waiting.
    update public.listings as l
    set status = 'sold'
    where l.id = listing.id
      and l.stock = 0
      and not exists (select 1 from public.reservations as r
                      where r.listing_id = l.id and r.status in ('requested', 'accepted'));
  end if;

  select l.status into listing_status from public.listings as l where l.id = listing.id;

  other := case when uid = rv.buyer_id then rv.seller_id else rv.buyer_id end;
  perform public.notify(other, 'reservation_' || new_status,
    case new_status when 'accepted' then 'Reservation accepted'
                    when 'declined' then 'Reservation declined'
                    when 'cancelled' then 'Reservation cancelled'
                    else 'Marked as collected' end,
    format('%s × %s', rv.qty, listing.title), 'reservation:' || rv.id);

  return jsonb_build_object('reservation_id', rv.id, 'status', new_status, 'listing_status', listing_status);
end;
$$;

-- What My Reservations shows: one row per reservation, with the listing and
-- the other party. Contact email is shared only once the seller accepts.
create type public.reservation_card as (
  id uuid,
  listing_id uuid,
  listing_title text,
  listing_photo text,
  pickup_area text,
  price_sen integer,
  qty integer,
  pickup_note text,
  status text,
  expires_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  i_am_buyer boolean,
  other_party_name text,
  other_party_email text
);

create function public.my_reservations(side text default 'buying')
returns setof public.reservation_card
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  stale uuid;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if side is null or side not in ('buying', 'selling') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose buying or selling.');
  end if;

  -- Lazy expiry for the listings this user is involved with.
  for stale in
    select distinct rv.listing_id from public.reservations as rv
    where (rv.buyer_id = uid or rv.seller_id = uid)
      and rv.status in ('requested', 'accepted') and rv.expires_at <= now()
  loop
    perform 1 from public.listings as l where l.id = stale for update;
    perform public.expire_listing_reservations(stale);
  end loop;

  return query
  select rv.id, rv.listing_id, l.title, l.photo_paths[1], l.pickup_area, l.price_sen,
         rv.qty, rv.pickup_note, rv.status, rv.expires_at, rv.created_at, rv.updated_at,
         rv.buyer_id = uid,
         p.name,
         case when rv.status in ('accepted', 'collected') then p.email end
  from public.reservations as rv
  join public.listings as l on l.id = rv.listing_id
  join public.profiles as p on p.id = case when rv.buyer_id = uid then rv.seller_id else rv.buyer_id end
  where case when side = 'buying' then rv.buyer_id = uid else rv.seller_id = uid end
  order by (rv.status in ('requested', 'accepted')) desc, rv.created_at desc;
end;
$$;

------------------------------------------------------------------------------
-- Listings: can't be closed or marked sold while reservations are active
------------------------------------------------------------------------------

create or replace function public.set_listing_status(listing_id uuid, new_status text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  listing public.listings;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to sell.');
  end if;
  if new_status is null or new_status not in ('draft', 'available', 'reserved', 'sold', 'closed') then
    perform public.raise_app_error('INVALID_INPUT', 'Unknown listing status.');
  end if;

  select * into listing from public.listings as l where l.id = set_listing_status.listing_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
  if listing.owner_id <> auth.uid() then
    perform public.raise_app_error('FORBIDDEN', 'You can only change your own listings.');
  end if;

  if public.expire_listing_reservations(listing.id) > 0 then
    select * into listing from public.listings as l where l.id = listing.id;
  end if;

  if (listing.status, new_status) not in (
    ('draft', 'available'), ('draft', 'closed'),
    ('available', 'closed'), ('available', 'sold'),
    ('closed', 'available')
  ) then
    perform public.raise_app_error('INVALID_TRANSITION',
      format('This listing is %s, so it can''t be changed to %s.', listing.status, new_status));
  end if;
  if new_status = 'available' and cardinality(listing.photo_paths) = 0 then
    perform public.raise_app_error('INVALID_INPUT', 'Add at least one photo before publishing.');
  end if;
  if new_status in ('closed', 'sold') and exists (
    select 1 from public.reservations as rv
    where rv.listing_id = listing.id and rv.status in ('requested', 'accepted')
  ) then
    perform public.raise_app_error('INVALID_TRANSITION',
      'This listing has reservations in progress. Resolve them first.');
  end if;

  update public.listings as l set
    status = new_status,
    -- Marking sold means every remaining unit went (sold outside the app).
    stock = case when new_status = 'sold' then 0 else l.stock end
  where l.id = listing.id;

  return jsonb_build_object('listing_id', listing.id, 'status', new_status);
end;
$$;

------------------------------------------------------------------------------
-- Row Level Security and privileges
------------------------------------------------------------------------------

alter table public.reservations enable row level security;
alter table public.notifications enable row level security;

revoke all on public.reservations, public.notifications from anon, authenticated;
grant select on public.reservations, public.notifications to authenticated;
-- The only client write: marking one's own notification read.
grant update (read) on public.notifications to authenticated;

create policy "Buyers and sellers see their reservations; admins see all"
  on public.reservations for select to authenticated
  using (buyer_id = (select auth.uid()) or seller_id = (select auth.uid()) or (select public.is_admin()));

create policy "Users read their own notifications"
  on public.notifications for select to authenticated
  using (recipient_id = (select auth.uid()));

create policy "Users mark their own notifications read"
  on public.notifications for update to authenticated
  using (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

revoke execute on function
  public.notify(uuid, text, text, text, text),
  public.expire_listing_reservations(uuid)
from public, anon, authenticated;

revoke execute on function
  public.request_reservation(uuid, integer, text),
  public.resolve_reservation(uuid, text),
  public.my_reservations(text)
from public, anon;

grant execute on function
  public.request_reservation(uuid, integer, text),
  public.resolve_reservation(uuid, text),
  public.my_reservations(text)
to authenticated;
