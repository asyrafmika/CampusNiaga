-- CampusNiaga Phase 6 (M5): the business dashboard. See
-- docs/data-dictionary.md ("orders.cost_sen") and docs/api-contracts.md.
--
-- Security and truthfulness:
--   * Every figure comes from SQL aggregates over the caller's own business.
--     The functions take no business id: they derive it from auth.uid(), so
--     one seller can never ask for another's numbers.
--   * Approved businesses only (owns_business), read live.
--   * Revenue is the sum of totals of orders the seller marked completed,
--     and costs are what the seller entered: estimated and self-reported.
--     No payment is taken or verified.

------------------------------------------------------------------------------
-- Recording costs
------------------------------------------------------------------------------

create function public.set_order_cost(order_id uuid, cost_sen integer)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  o public.orders;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if set_order_cost.cost_sen is not null and set_order_cost.cost_sen not between 0 and 100000000 then
    perform public.raise_app_error('INVALID_INPUT', 'The cost must be between RM 0 and RM 1,000,000.');
  end if;

  select * into o from public.orders as ord where ord.id = set_order_cost.order_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Order not found.');
  end if;
  if not public.owns_business(o.business_id) then
    perform public.raise_app_error('FORBIDDEN', 'Only the approved business that sold it can record its cost.');
  end if;
  if o.status = 'cancelled' then
    perform public.raise_app_error('INVALID_TRANSITION', 'A cancelled order has no cost to record.');
  end if;

  update public.orders as ord set cost_sen = set_order_cost.cost_sen where ord.id = o.id;
  return jsonb_build_object('order_id', o.id, 'cost_sen', set_order_cost.cost_sen);
end;
$$;

------------------------------------------------------------------------------
-- The seller sees their own cost in My Orders (never the buyer)
------------------------------------------------------------------------------

alter type public.order_card add attribute cost_sen integer;

create or replace function public.my_orders(side text default 'buying', page_size integer default 50, page_offset integer default 0)
returns setof public.order_card
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if my_orders.side is null or my_orders.side not in ('buying', 'selling') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose buying or selling.');
  end if;
  if my_orders.page_size is null or my_orders.page_size not between 1 and 100
     or my_orders.page_offset is null or my_orders.page_offset < 0 then
    perform public.raise_app_error('INVALID_INPUT', 'Ask for 1 to 100 orders from a non-negative offset.');
  end if;

  return query
  select o.id, o.listing_id, l.title, l.photo_paths[1], o.business_id, b.name, o.campaign_id, c.title,
         o.qty, o.unit_price_sen, o.total_sen, o.status, o.buyer_note, o.collection_details, o.cancelled_by,
         o.created_at, o.updated_at, o.completed_at,
         o.buyer_id = uid,
         p.name,
         case when o.status in ('confirmed', 'preparing', 'ready_for_pickup', 'completed') then p.email end,
         case when my_orders.side = 'selling' then o.cost_sen end
  from public.orders as o
  join public.listings as l on l.id = o.listing_id
  join public.businesses as b on b.id = o.business_id
  left join public.campaigns as c on c.id = o.campaign_id
  join public.profiles as p on p.id = case when my_orders.side = 'buying' then b.owner_id else o.buyer_id end
  where case when my_orders.side = 'buying' then o.buyer_id = uid else b.owner_id = uid end
  order by (o.status not in ('completed', 'cancelled')) desc, o.created_at desc, o.id
  limit my_orders.page_size
  offset my_orders.page_offset;
end;
$$;

------------------------------------------------------------------------------
-- The dashboard
------------------------------------------------------------------------------

create function public.business_dashboard(from_at timestamptz default null, to_at timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  business public.businesses;
  by_status jsonb;
  total_orders integer;
  completed_count integer;
  revenue bigint;
  cost bigint;
  costed integer;
  top jsonb;
  stock jsonb;
  campaigns jsonb;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  -- The caller's own business; there is no way to name another one.
  select * into business from public.businesses as b where b.owner_id = auth.uid();
  if not found or not public.owns_business(business.id) then
    perform public.raise_app_error('FORBIDDEN', 'The dashboard is for approved businesses.');
  end if;
  if business_dashboard.from_at is not null and business_dashboard.to_at is not null
     and business_dashboard.from_at >= business_dashboard.to_at then
    perform public.raise_app_error('INVALID_INPUT', 'The start of the range must be before its end.');
  end if;

  -- Orders placed in the range, by status (zeros included).
  select jsonb_object_agg(s.status, coalesce(n.total, 0) order by s.ord), coalesce(sum(n.total), 0)::integer
  into by_status, total_orders
  from unnest(array['pending_confirmation', 'confirmed', 'preparing', 'ready_for_pickup', 'completed', 'cancelled'])
       with ordinality as s (status, ord)
  left join (
    select o.status, count(*)::integer as total
    from public.orders as o
    where o.business_id = business.id
      and (business_dashboard.from_at is null or o.created_at >= business_dashboard.from_at)
      and (business_dashboard.to_at is null or o.created_at < business_dashboard.to_at)
    group by o.status
  ) as n on n.status = s.status;

  -- Orders completed in the range: the estimated, self-reported figures.
  select count(*)::integer, coalesce(sum(o.total_sen), 0)::bigint,
         coalesce(sum(o.cost_sen), 0)::bigint, count(o.cost_sen)::integer
  into completed_count, revenue, cost, costed
  from public.orders as o
  where o.business_id = business.id
    and o.status = 'completed'
    and (business_dashboard.from_at is null or o.completed_at >= business_dashboard.from_at)
    and (business_dashboard.to_at is null or o.completed_at < business_dashboard.to_at);

  select coalesce(jsonb_agg(t order by t.revenue_sen desc, t.units desc, t.title), '[]'::jsonb) into top
  from (
    select o.listing_id, l.title, sum(o.qty)::integer as units, sum(o.total_sen)::bigint as revenue_sen
    from public.orders as o
    join public.listings as l on l.id = o.listing_id
    where o.business_id = business.id
      and o.status = 'completed'
      and (business_dashboard.from_at is null or o.completed_at >= business_dashboard.from_at)
      and (business_dashboard.to_at is null or o.completed_at < business_dashboard.to_at)
    group by o.listing_id, l.title
    order by revenue_sen desc, units desc, l.title
    limit 5
  ) as t;

  select coalesce(jsonb_agg(jsonb_build_object(
           'listing_id', l.id, 'title', l.title, 'status', l.status, 'stock', l.stock, 'hidden', l.hidden)
         order by l.stock, l.title), '[]'::jsonb)
  into stock
  from public.listings as l
  where l.business_id = business.id and l.status <> 'draft';

  select coalesce(jsonb_agg(jsonb_build_object(
           'campaign_id', c.id, 'title', c.title, 'status', c.status, 'capacity', c.capacity,
           'allocated_qty', c.allocated_qty, 'remaining', c.capacity - c.allocated_qty, 'close_at', c.close_at)
         order by c.close_at), '[]'::jsonb)
  into campaigns
  from public.campaigns as c
  where c.business_id = business.id and c.status in ('draft', 'open');

  return jsonb_build_object(
    'business_id', business.id,
    'business_name', business.name,
    'from_at', business_dashboard.from_at,
    'to_at', business_dashboard.to_at,
    'orders_by_status', by_status,
    'total_orders', total_orders,
    'completed_count', completed_count,
    'estimated_revenue_sen', revenue,
    'recorded_cost_sen', cost,
    'costed_completed_count', costed,
    'estimated_profit_sen', revenue - cost,
    'top_products', top,
    'stock', stock,
    'campaigns', campaigns
  );
end;
$$;

------------------------------------------------------------------------------
-- Function privileges
------------------------------------------------------------------------------

revoke execute on function
  public.set_order_cost(uuid, integer),
  public.business_dashboard(timestamptz, timestamptz)
from public, anon;

grant execute on function
  public.set_order_cost(uuid, integer),
  public.business_dashboard(timestamptz, timestamptz)
to authenticated;
