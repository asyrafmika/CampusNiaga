#!/usr/bin/env bash
# Phase 2 pass condition, for real: two buyers buy the last unit at the
# same moment, on two separate database connections. Exactly one must win.
#
# Buyer A's transaction buys the unit and keeps its transaction open for
# 3 seconds. Buyer B starts 1 second later. buy_item() locks the
# listing row, so B must wait until A commits, then find no units left.
#
# Runs in CI against the throwaway local database from `supabase db start`.
set -uo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
q() { psql "$DB_URL" -v ON_ERROR_STOP=1 -qtAX -c "$1"; }

seller=a0000000-0000-0000-0000-00000000000a
buyer_a=b0000000-0000-0000-0000-00000000000b
buyer_b=c0000000-0000-0000-0000-00000000000c
listing=d0000000-0000-0000-0000-00000000000d
out=$(mktemp -d)

q "insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
     ('$seller', 'race.seller@student.usm.my', now(), '{\"name\": \"Seller\"}'),
     ('$buyer_a', 'race.a@student.usm.my', now(), '{\"name\": \"Buyer A\"}'),
     ('$buyer_b', 'race.b@student.usm.my', now(), '{\"name\": \"Buyer B\"}');" || exit 1
q "insert into public.listings (id, owner_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status)
   values ('$listing', '$seller', 'Last calculator', 'last calculator', 'Stationery', 2500, 'good', array['p/1.jpg'], 1, 'Tekun', 'available');" || exit 1

# $1 buyer id, $2 seconds to hold the transaction open after buying.
attempt() {
  psql "$DB_URL" -qtAX <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "$1", "role": "authenticated"}', true);
select 'RESULT ' || (public.buy_item('$listing') ->> 'status');
select pg_sleep($2);
commit;
SQL
}

attempt "$buyer_a" 3 >"$out/a.txt" 2>&1 &
pid_a=$!
sleep 1
start_b=$(date +%s.%N)
attempt "$buyer_b" 0 >"$out/b.txt" 2>&1 &
pid_b=$!
wait "$pid_a"; wait "$pid_b"
end_b=$(date +%s.%N)

echo "--- buyer A"; cat "$out/a.txt"
echo "--- buyer B"; cat "$out/b.txt"

purchases=$(q "select count(*) from public.purchases where listing_id = '$listing';")
listing_state=$(q "select status || '/' || stock from public.listings where id = '$listing';")
waited=$(awk -v s="$start_b" -v e="$end_b" 'BEGIN { print (e - s >= 1.5) ? "yes" : "no" }')

echo "--- purchases: $purchases, listing: $listing_state, buyer B waited for the lock: $waited"

fail=0
grep -q 'RESULT awaiting_handover' "$out/a.txt" || { echo "FAIL: buyer A should have bought the unit"; fail=1; }
grep -q 'ITEM_UNAVAILABLE' "$out/b.txt" || { echo "FAIL: buyer B should have been refused with ITEM_UNAVAILABLE"; fail=1; }
[ "$purchases" = "1" ] || { echo "FAIL: expected exactly 1 purchase, found $purchases"; fail=1; }
[ "$listing_state" = "sold/0" ] || { echo "FAIL: expected the listing sold with 0 stock, found $listing_state"; fail=1; }
[ "$waited" = "yes" ] || { echo "FAIL: buyer B did not wait for buyer A's lock"; fail=1; }

[ "$fail" = 0 ] && echo "PASS: one unit, two simultaneous buyers, exactly one purchase"
exit "$fail"
