#!/usr/bin/env bash
# Phase 4 pass condition, for real: two buyers order the last unit of ready
# stock, and the last place of a pre-order, at the same moment on two
# separate database connections. Exactly one may win each time.
#
# Buyer A's transaction orders and keeps its transaction open for 3 seconds.
# Buyer B starts 1 second later. place_order() locks the listing (ready
# stock) or the campaign (pre-order), so B must wait until A commits, then
# find nothing left.
#
# Runs in CI against the throwaway local database from `supabase db start`.
set -uo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
q() { psql "$DB_URL" -v ON_ERROR_STOP=1 -qtAX -c "$1"; }

seller=a1000000-0000-0000-0000-00000000000a
buyer_a=b1000000-0000-0000-0000-00000000000b
buyer_b=c1000000-0000-0000-0000-00000000000c
application=e1000000-0000-0000-0000-00000000000e
business=f1000000-0000-0000-0000-00000000000f
listing=d1000000-0000-0000-0000-00000000000d
campaign=d2000000-0000-0000-0000-00000000000d
out=$(mktemp -d)

q "insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
     ('$seller', 'order.seller@student.usm.my', now(), '{\"name\": \"Seller\"}'),
     ('$buyer_a', 'order.a@student.usm.my', now(), '{\"name\": \"Buyer A\"}'),
     ('$buyer_b', 'order.b@student.usm.my', now(), '{\"name\": \"Buyer B\"}');" || exit 1
q "insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at)
   values ('$application', '$seller', 'Race Bakes', 'Food & Beverage', 'Brownies for the race test.', '012-3456789', 'Tekun lobby', 'approved', now(), now());" || exit 1
q "insert into public.businesses (id, owner_id, application_id, name, pickup_details) values ('$business', '$seller', '$application', 'Race Bakes', 'Tekun lobby');" || exit 1
q "insert into public.listings (id, owner_id, mode, business_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status)
   values ('$listing', '$seller', 'business', '$business', 'Last brownie box', 'last brownie box', 'Food & Beverage', 1200, 'new', array['p/1.jpg'], 1, 'Tekun', 'available');" || exit 1
q "insert into public.campaigns (id, business_id, listing_id, title, price_sen, start_at, close_at, capacity, pickup_details, status)
   values ('$campaign', '$business', '$listing', 'Last pre-order place', 1000, now() - interval '1 hour', now() + interval '1 day', 1, 'Tekun lobby', 'open');" || exit 1

# $1 buyer id, $2 campaign id or null, $3 seconds to hold the transaction open.
attempt() {
  local campaign_arg="null"
  [ "$2" != "null" ] && campaign_arg="'$2'"
  psql "$DB_URL" -qtAX <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "$1", "role": "authenticated"}', true);
select 'RESULT ' || (public.place_order('$listing', 1, $campaign_arg) ->> 'status');
select pg_sleep($3);
commit;
SQL
}

# $1 label, $2 campaign id or null, $3 the reason buyer B must get.
race() {
  attempt "$buyer_a" "$2" 3 >"$out/$1-a.txt" 2>&1 &
  local pid_a=$!
  sleep 1
  local start_b; start_b=$(date +%s.%N)
  attempt "$buyer_b" "$2" 0 >"$out/$1-b.txt" 2>&1 &
  local pid_b=$!
  wait "$pid_a"; wait "$pid_b"
  local end_b; end_b=$(date +%s.%N)

  echo "--- $1: buyer A"; cat "$out/$1-a.txt"
  echo "--- $1: buyer B"; cat "$out/$1-b.txt"
  local waited; waited=$(awk -v s="$start_b" -v e="$end_b" 'BEGIN { print (e - s >= 1.5) ? "yes" : "no" }')
  echo "--- $1: buyer B waited for the lock: $waited"

  grep -q 'RESULT pending_confirmation' "$out/$1-a.txt" || { echo "FAIL ($1): buyer A should have ordered"; fail=1; }
  grep -q "$3" "$out/$1-b.txt" || { echo "FAIL ($1): buyer B should have been refused with $3"; fail=1; }
  [ "$waited" = "yes" ] || { echo "FAIL ($1): buyer B did not wait for buyer A's lock"; fail=1; }
}

fail=0
race "ready stock" null ITEM_UNAVAILABLE
race "pre-order" "$campaign" CAPACITY_FULL

stock_orders=$(q "select count(*) from public.orders where listing_id = '$listing' and campaign_id is null;")
pre_orders=$(q "select count(*) from public.orders where campaign_id = '$campaign';")
listing_state=$(q "select status || '/' || stock from public.listings where id = '$listing';")
allocation=$(q "select allocated_qty || '/' || capacity from public.campaigns where id = '$campaign';")
echo "--- ready-stock orders: $stock_orders, listing: $listing_state; pre-orders: $pre_orders, allocation: $allocation"

[ "$stock_orders" = "1" ] || { echo "FAIL: expected exactly 1 ready-stock order, found $stock_orders"; fail=1; }
[ "$listing_state" = "sold/0" ] || { echo "FAIL: expected the listing sold with 0 stock, found $listing_state"; fail=1; }
[ "$pre_orders" = "1" ] || { echo "FAIL: expected exactly 1 pre-order, found $pre_orders"; fail=1; }
[ "$allocation" = "1/1" ] || { echo "FAIL: expected allocation 1/1, found $allocation"; fail=1; }

[ "$fail" = 0 ] && echo "PASS: two simultaneous buyers never exceed the stock or the capacity"
exit "$fail"
