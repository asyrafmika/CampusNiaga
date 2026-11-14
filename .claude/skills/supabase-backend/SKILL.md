---
name: supabase-backend
description: Implement or modify CampusNiaga's Supabase backend under supabase/, including SQL migrations, tables and constraints, Row Level Security policies and column privileges, SECURITY DEFINER database functions called over RPC, triggers, transactions and row locking, Storage buckets and policies, the audit log, rate limiting, full-text search, and the M4 opportunity ranking. Use for any schema, policy, database function or storage work. Who-may-do-what decisions (the student check, staff roles, business ownership) belong to authentication-authorization; M2 state rules belong to business-registration-workflow.
---

# Supabase backend: `supabase/`

Read `CLAUDE.md` first. Its "Database rules for every migration", data conventions and error reasons apply here and aren't repeated.

The hosted project is the user's development environment. **Never run `supabase db push` or change project settings unless the user asks.** Tests run in CI on a throwaway local database (this machine has no Docker).

## Folder structure

```
supabase/
├─ config.toml                 CLI config for the local stack CI starts
├─ migrations/
│  └─ YYYYMMDDHHMMSS_name.sql  one change each; never edit one already pushed
└─ tests/database/
   └─ NN_area.test.sql         pgTAP, one transaction per file, rolled back
```

## Anatomy of a privileged database function

```sql
create function public.request_reservation(listing_id uuid, pickup_note text)
returns jsonb
language plpgsql
volatile
security definer          -- runs as the owner, so it can write what clients can't
set search_path = ''      -- no search_path hijacking; name everything with its schema
as $$
declare
  listing public.listings;
begin
  if not public.is_student() then                              -- 1. who is calling
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM email first.');
  end if;
  if pickup_note is not null and char_length(pickup_note) > 200 then   -- 2. input
    perform public.raise_app_error('INVALID_INPUT', 'Pickup note is too long.');
  end if;
  select * into listing from public.listings where id = listing_id for update;  -- 3. lock
  if not found then perform public.raise_app_error('NOT_FOUND', 'Listing not found.'); end if;
  if listing.status <> 'available' or listing.hidden then
    perform public.raise_app_error('ITEM_UNAVAILABLE', 'This item is no longer available.');
  end if;
  -- 4. change + audit in the same transaction ...
  return jsonb_build_object('reservation_id', ...);            -- 5. small result
end;
$$;

revoke execute on function public.request_reservation(uuid, text) from public, anon;
grant execute on function public.request_reservation(uuid, text) to authenticated;
```

- Never accept `owner_id`, `status`, `role`, `business_id`, `total_sen` or `allocated_qty` as input. Derive them from `auth.uid()` and stored rows.
- Validate with explicit checks plus table `check` constraints; return a small `jsonb` result.
- A parameter with the same name as a column must be qualified (`function_name.param`) where both are in scope.

## Transactions and invariants

A function body is one transaction. Lock the rows you check with `select … for update` before deciding:

| Operation | Lock and check | Fail with |
|---|---|---|
| Request reservation | listing `available`, not own, not hidden; no active reservation | `ITEM_UNAVAILABLE`, `ALREADY_EXISTS` |
| Accept reservation | listing + reservation; set listing `reserved` | `INVALID_TRANSITION` |
| Ready-stock order | listing `stock >= qty`, then decrement | `ITEM_UNAVAILABLE` |
| Pre-order | campaign `open`, within dates, `allocated_qty + qty <= capacity`, per-order limit | `CAPACITY_FULL`, `INVALID_TRANSITION` |
| Cancel/reject order | order + campaign or listing; release quantity | `INVALID_TRANSITION` |

- Also add `check` constraints as a last line of defence (`stock >= 0`, `allocated_qty <= capacity`).
- State machines: a `status` check constraint plus an explicit allowed-transition check in the function (`if (old, new) not in (...) then INVALID_TRANSITION`).
- Orders snapshot `unit_price_sen` and `total_sen = unit_price_sen * qty` at creation.
- Hidden listings are excluded from feeds, reservations, orders and M4 supply.
- Reservation expiry is lazy: treat `requested`/`accepted` past `expires_at` as `expired` when read or acted on, and store it then.

## Row Level Security patterns

```sql
alter table public.listings enable row level security;
revoke all on public.listings from anon, authenticated;
grant select on public.listings to authenticated;

create policy "Students see visible listings; owners see their own"
  on public.listings for select to authenticated
  using ((not hidden and status <> 'draft' and (select public.is_student()))
         or owner_id = (select auth.uid()));
```

- One policy per action and audience, named in plain English.
- Clients write directly only their own non-privileged data (profile name, application drafts, marking a notification read). Use column-level grants (`grant update (name) …`) so a policy can't be used to change other columns.
- Tables written only by functions get no insert/update/delete grants at all.

## Storage

Buckets and paths are in `docs/data-dictionary.md`. Create buckets and their `storage.objects` policies in a migration. Make paths start with the owner's id, and check `(storage.foldername(name))[1] = auth.uid()::text`. Keep `application-documents` private and serve it through short-lived signed URLs.

## Search, totals and M4

- **Search:** a generated `search_vector tsvector` column with a GIN index, queried with `websearch_to_tsquery`, paginated with `range`/keyset.
- **M5 totals:** SQL `sum`/`count`/`group by` over the seller's completed orders filtered by `completed_at`, exposed through a function that checks ownership.
- **M4:** pure SQL functions in steps:
  1. Normalize the text: lowercase, strip punctuation, simple singular forms, stop words, and a small curated synonym table.
  2. Build a cluster key from the category plus the head terms.
  3. Demand `D` is the count of distinct students (request creators plus interests).
  4. Supply `S` is the matching visible listings, plus the number of distinct sellers and the median prices.
  5. `score = greatest(0, 5*least(D,20) - 8*least(S,10) + case when market median > preferred median then 10 else 0 end)`.
  6. Write `reasons` built from the same numbers; mark `insufficient_data` when `D < 2`.

  Store `algo_version` and parameters. Recompute affected clusters from triggers on requests, interests and listings.

## Workflow

1. Update `docs/data-dictionary.md` and `docs/api-contracts.md`.
2. Write the migration: tables and constraints, then revokes and grants, RLS and policies, functions, and function grants.
3. Write pgTAP tests: allowed and refused for every policy and function, plus invariants and transitions (`unit-testing`).
4. Push the branch. CI's database job applies the migrations to a fresh database, lints them and runs the tests. Fix anything red.
5. Only when the user asks: `npx supabase@2.122.0 db push` to the hosted project.

## Verification checklist

- [ ] RLS is enabled on every new table; client privileges are revoked, then only what a policy covers is granted.
- [ ] Every `security definer` function has `set search_path = ''`, checks the caller first, and has execute revoked from `public, anon`.
- [ ] No client-supplied owner, role, status or price is trusted.
- [ ] Conflicting changes lock their rows; the audit entry is written in the same function.
- [ ] Each policy and function has allowed and refused pgTAP tests; CI is green.
- [ ] No migration that was already pushed was edited.
