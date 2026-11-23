-- Student entrepreneurship performance for administrators (ADR 0007).
-- See docs/api-contracts.md ("Business performance for administrators").
--
-- Security and privacy:
--   * Admins only, read live. Reviewers, students and owners are refused.
--   * Orders, estimated revenue, best sellers, stock and pre-order places.
--     Never a seller's cost or profit: they record those for their own use.
--   * Both functions write an audit entry, because an admin is looking at
--     someone else's figures.
--   * The owner's dashboard and the admin's page share business_figures(),
--     so the two can't drift apart.
--
-- This also closes a leak. orders.cost_sen was granted with the rest of the
-- row, so a buyer (or an admin) could read it straight from the table. It is
-- now readable only through business_dashboard() and my_orders('selling').

------------------------------------------------------------------------------
-- A seller's cost is not selectable
------------------------------------------------------------------------------

-- A column can't be revoked from a table-wide grant, so grant the others.
-- A column added to orders later must be granted explicitly.
revoke select on public.orders from authenticated;
grant select (
  id, buyer_id, business_id, listing_id, campaign_id, qty, unit_price_sen, total_sen,
  status, buyer_note, collection_details, cancelled_by, completed_at, created_at, updated_at
) on public.orders to authenticated;

------------------------------------------------------------------------------
-- The figures, for one business (internal: callers check who may see them)
------------------------------------------------------------------------------

create function public.business_figures(target_business uuid, from_at timestamptz, to_at timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
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
  -- Orders placed in the range, by status (zeros included).
  select jsonb_object_agg(s.status, coalesce(n.total, 0) order by s.ord), coalesce(sum(n.total), 0)::integer
  into by_status, total_orders
  from unnest(array['pending_confirmation', 'confirmed', 'preparing', 'ready_for_pickup', 'completed', 'cancelled'])
       with ordinality as s (status, ord)
  left join (
    select o.status, count(*)::integer as total
    from public.orders as o
    where o.business_id = target_business
      and (business_figures.from_at is null or o.created_at >= business_figures.from_at)
      and (business_figures.to_at is null or o.created_at < business_figures.to_at)
    group by o.status
  ) as n on n.status = s.status;

  -- Orders completed in the range: the estimated, self-reported figures.
  select count(*)::integer, coalesce(sum(o.total_sen), 0)::bigint,
         coalesce(sum(o.cost_sen), 0)::bigint, count(o.cost_sen)::integer
  into completed_count, revenue, cost, costed
  from public.orders as o
  where o.business_id = target_business
    and o.status = 'completed'
    and (business_figures.from_at is null or o.completed_at >= business_figures.from_at)
    and (business_figures.to_at is null or o.completed_at < business_figures.to_at);

  select coalesce(jsonb_agg(t order by t.revenue_sen desc, t.units desc, t.title), '[]'::jsonb) into top
  from (
    select o.listing_id, l.title, sum(o.qty)::integer as units, sum(o.total_sen)::bigint as revenue_sen
    from public.orders as o
    join public.listings as l on l.id = o.listing_id
    where o.business_id = target_business
      and o.status = 'completed'
      and (business_figures.from_at is null or o.completed_at >= business_figures.from_at)
      and (business_figures.to_at is null or o.completed_at < business_figures.to_at)
    group by o.listing_id, l.title
    order by revenue_sen desc, units desc, l.title
    limit 5
  ) as t;

  select coalesce(jsonb_agg(jsonb_build_object(
           'listing_id', l.id, 'title', l.title, 'status', l.status, 'stock', l.stock, 'hidden', l.hidden)
         order by l.stock, l.title), '[]'::jsonb)
  into stock
  from public.listings as l
  where l.business_id = target_business and l.status <> 'draft';

  select coalesce(jsonb_agg(jsonb_build_object(
           'campaign_id', c.id, 'title', c.title, 'status', c.status, 'capacity', c.capacity,
           'allocated_qty', c.allocated_qty, 'remaining', c.capacity - c.allocated_qty, 'close_at', c.close_at)
         order by c.close_at), '[]'::jsonb)
  into campaigns
  from public.campaigns as c
  where c.business_id = target_business and c.status in ('draft', 'open');

  return jsonb_build_object(
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

-- Same output as Phase 6, from the shared figures.
create or replace function public.business_dashboard(from_at timestamptz default null, to_at timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  business public.businesses;
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

  return jsonb_build_object(
    'business_id', business.id,
    'business_name', business.name,
    'from_at', business_dashboard.from_at,
    'to_at', business_dashboard.to_at
  ) || public.business_figures(business.id, business_dashboard.from_at, business_dashboard.to_at);
end;
$$;

------------------------------------------------------------------------------
-- Administrators
------------------------------------------------------------------------------

-- Every business with its headline figures, highest revenue first, and the
-- totals across all of them.
create function public.admin_business_performance_list(
  from_at timestamptz default null,
  to_at timestamptz default null,
  page_size integer default 20,
  page_offset integer default 0
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  result jsonb;
begin
  if not public.is_admin() then
    perform public.raise_app_error('FORBIDDEN', 'Administrator access required.');
  end if;
  if admin_business_performance_list.from_at is not null and admin_business_performance_list.to_at is not null
     and admin_business_performance_list.from_at >= admin_business_performance_list.to_at then
    perform public.raise_app_error('INVALID_INPUT', 'The start of the range must be before its end.');
  end if;
  if admin_business_performance_list.page_size is null
     or admin_business_performance_list.page_size not between 1 and 100
     or admin_business_performance_list.page_offset is null
     or admin_business_performance_list.page_offset < 0 then
    perform public.raise_app_error('INVALID_INPUT', 'Ask for 1 to 100 businesses from a non-negative offset.');
  end if;

  with placed as (
    select o.business_id, count(*)::integer as n
    from public.orders as o
    where (admin_business_performance_list.from_at is null or o.created_at >= admin_business_performance_list.from_at)
      and (admin_business_performance_list.to_at is null or o.created_at < admin_business_performance_list.to_at)
    group by o.business_id
  ), done as (
    select o.business_id, count(*)::integer as n, sum(o.total_sen)::bigint as revenue
    from public.orders as o
    where o.status = 'completed'
      and (admin_business_performance_list.from_at is null or o.completed_at >= admin_business_performance_list.from_at)
      and (admin_business_performance_list.to_at is null or o.completed_at < admin_business_performance_list.to_at)
    group by o.business_id
  ), figures as (
    select b.id as business_id, b.name as business_name, p.name as owner_name, a.category, b.status,
           coalesce(placed.n, 0) as total_orders,
           coalesce(done.n, 0) as completed_count,
           coalesce(done.revenue, 0)::bigint as estimated_revenue_sen
    from public.businesses as b
    join public.profiles as p on p.id = b.owner_id
    join public.business_applications as a on a.id = b.application_id
    left join placed on placed.business_id = b.id
    left join done on done.business_id = b.id
  ), page as (
    select * from figures as f
    order by f.estimated_revenue_sen desc, f.total_orders desc, f.business_name, f.business_id
    limit admin_business_performance_list.page_size
    offset admin_business_performance_list.page_offset
  )
  select jsonb_build_object(
    'totals', (
      select jsonb_build_object(
        'businesses', count(*),
        'approved_businesses', count(*) filter (where f.status = 'approved'),
        'total_orders', coalesce(sum(f.total_orders), 0),
        'completed_count', coalesce(sum(f.completed_count), 0),
        'estimated_revenue_sen', coalesce(sum(f.estimated_revenue_sen), 0))
      from figures as f),
    'rows', coalesce((
      select jsonb_agg(to_jsonb(g)
                       order by g.estimated_revenue_sen desc, g.total_orders desc, g.business_name, g.business_id)
      from page as g), '[]'::jsonb)
  ) into result;

  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values (uid, 'performance.list_viewed', 'business', 'all',
          jsonb_strip_nulls(jsonb_build_object('from', admin_business_performance_list.from_at,
                                               'to', admin_business_performance_list.to_at)));

  return result;
end;
$$;

-- One business, suspended ones included. The keys are listed one by one, so
-- a private figure added to business_figures() can't slip through.
create function public.admin_business_performance(
  business_id uuid,
  from_at timestamptz default null,
  to_at timestamptz default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  business public.businesses;
  v_owner text;
  v_category text;
  f jsonb;
begin
  if not public.is_admin() then
    perform public.raise_app_error('FORBIDDEN', 'Administrator access required.');
  end if;
  if admin_business_performance.from_at is not null and admin_business_performance.to_at is not null
     and admin_business_performance.from_at >= admin_business_performance.to_at then
    perform public.raise_app_error('INVALID_INPUT', 'The start of the range must be before its end.');
  end if;
  select * into business from public.businesses as b where b.id = admin_business_performance.business_id;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Business not found.');
  end if;
  select p.name into v_owner from public.profiles as p where p.id = business.owner_id;
  select a.category into v_category from public.business_applications as a where a.id = business.application_id;

  f := public.business_figures(business.id, admin_business_performance.from_at, admin_business_performance.to_at);

  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values (uid, 'performance.viewed', 'business', business.id::text,
          jsonb_strip_nulls(jsonb_build_object('business', business.name,
                                               'from', admin_business_performance.from_at,
                                               'to', admin_business_performance.to_at)));

  return jsonb_build_object(
    'business_id', business.id,
    'business_name', business.name,
    'owner_name', v_owner,
    'category', v_category,
    'status', business.status,
    'approved_at', business.created_at,
    'orders_by_status', f -> 'orders_by_status',
    'total_orders', f -> 'total_orders',
    'completed_count', f -> 'completed_count',
    'estimated_revenue_sen', f -> 'estimated_revenue_sen',
    'top_products', f -> 'top_products',
    'stock', f -> 'stock',
    'campaigns', f -> 'campaigns'
  );
end;
$$;

------------------------------------------------------------------------------
-- Function privileges
------------------------------------------------------------------------------

revoke execute on function public.business_figures(uuid, timestamptz, timestamptz)
from public, anon, authenticated;

revoke execute on function
  public.admin_business_performance_list(timestamptz, timestamptz, integer, integer),
  public.admin_business_performance(uuid, timestamptz, timestamptz)
from public, anon;

grant execute on function
  public.admin_business_performance_list(timestamptz, timestamptz, integer, integer),
  public.admin_business_performance(uuid, timestamptz, timestamptz)
to authenticated;
