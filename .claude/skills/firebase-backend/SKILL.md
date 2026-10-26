---
name: firebase-backend
description: Implement or modify CampusNiaga's Firebase backend, including Cloud Functions in TypeScript under functions/, Firestore and Storage security rules and indexes under firebase/, the Firestore data model, transactions, triggers, audit logging, rate limiting, emulator configuration, and the M4 opportunity recommendation engine. Use for any callable, trigger, rules, index, schema or transaction work. Who-may-do-what decisions (claims, student gate, role helpers) belong to authentication-authorization; M2 state rules belong to business-registration-workflow.
---

# Firebase backend: `functions/` and `firebase/`

Cloud Functions v2, TypeScript, Node 22, region `asia-southeast1`. Development happens **only on the Emulator Suite**. Never run `firebase deploy` or touch a real project unless the user asks in the current task. Read `CLAUDE.md` for shared conventions and error reasons.

## Folder structure

```
functions/
├─ src/
│  ├─ index.ts                 exports only (re-export every callable and trigger)
│  ├─ callable/<area>/<name>.ts   thin handlers: guard -> parse -> service -> result
│  ├─ triggers/<area>/<name>.ts   Firestore/scheduled triggers (M4 recompute, counters)
│  ├─ services/<aggregate>Service.ts   transactions and multi-document writes
│  ├─ domain/                  pure TS: types.ts (mirror of data dictionary), state machines,
│  │                           money, normalization, opportunity scoring (no firebase imports)
│  └─ shared/
│     ├─ firebase.ts           initialized Admin SDK app/db/storage/auth (single instance)
│     ├─ errors.ts             fail(reason, message) -> HttpsError with details.reason
│     ├─ guards.ts             auth guard helpers (defined by authentication-authorization)
│     ├─ audit.ts              writeAudit(tx, entry) for use inside transactions
│     ├─ rateLimit.ts          per-uid sliding window counters
│     └─ clock.ts              now(): injectable for tests
├─ test/
│  ├─ unit/                    domain tests (no emulator)
│  └─ emulator/                rules tests and callable integration tests
firebase/
├─ firestore.rules
├─ storage.rules
└─ firestore.indexes.json
```

## Callable pattern (every callable looks like this)

```ts
export const requestReservation = onCall({ region: REGION }, async (req) => {
  const actor = requireStudent(req);                    // guard: claims + account status
  const input = parse(RequestReservationInput, req.data); // zod; throws INVALID_INPUT
  return reservationService.request(actor, input);      // transaction + audit inside
});
```

- Handlers contain no Firestore code. Services contain no request parsing.
- Inputs are zod schemas with bounds: string lengths, `priceSen` as an integer in 0..10_000_000, `qty` as an integer of at least 1, enum values from `domain/types.ts`. Unknown keys are stripped.
- Never accept `ownerUid`, `status`, `role`, `businessId`, `totalSen` or `allocatedQty` from the client. Derive them from the auth context and stored documents.
- Return small DTOs (`{ reservationId, status }`), not whole documents.
- Raise errors only through `fail(reason, message)` using the reason list in CLAUDE.md.

## Transactions and invariants

Use `db.runTransaction` for any read-then-write that another user could race:

| Operation | Read inside transaction | Fail with |
|---|---|---|
| Request reservation | listing (`status == 'available'`, not own, not hidden), existing active reservation | `ITEM_UNAVAILABLE`, `ALREADY_EXISTS` |
| Accept reservation | listing + reservation; set listing `reserved` | `INVALID_TRANSITION` |
| Place ready-stock order | listing `stock >= qty` → decrement | `ITEM_UNAVAILABLE` |
| Place pre-order | campaign `open`, within dates, `allocatedQty + qty <= capacity`, per-order limit | `CAPACITY_FULL`, `INVALID_TRANSITION` |
| Cancel/reject order | order + campaign or listing; release qty | `INVALID_TRANSITION` |

- State machines live in `domain/` as transition tables (`Record<Status, readonly Status[]>`). Services call `assertTransition(from, to)`.
- Every state change writes `statusHistory`/`updatedAt` and calls `writeAudit(tx, ...)` **in the same transaction**.
- Order documents snapshot `unitPriceSen` and `totalSen = unitPriceSen * qty` at creation, so later price edits don't change them.
- Banned or hidden listings are excluded from feeds, reservations, orders and M4 supply counts.

## Security rules structure

- Start with `match /{document=**} { allow read, write: if false; }` and open access per collection.
- Shared helper functions at the top of `firestore.rules` (`isSignedIn`, `isStudent`, `isReviewer`, `isAdmin`, `isOwner`, `ownsBusiness`) are **defined by the `authentication-authorization` skill**. Reuse them; don't redefine them.
- `listings` is read-only for clients; writes go through `upsertListing` / `setListingStatus`, which also build `searchTokens` with the shared normalizer (ADR 0002). Reservation expiry is lazy (no scheduler), and M5 figures use `count()`/`sum()` aggregation queries plus the `soldQty` counter.
- Direct client writes (where still allowed, e.g. profile name, application drafts) must restrict fields: `request.resource.data.diff(resource.data).affectedKeys().hasOnly([...])`, and validate types and sizes. Owner fields are immutable.
- Collections written only by functions (`auditLogs`, `opportunities`, `requestInterests`, `orders`, `campaigns.allocatedQty`, `businesses`, application status) have `allow write: if false` for clients.
- Storage: product photos at `listings/{uid}/{listingId}/{file}`, owner write, image/jpeg|png|webp, ≤ 5 MB, read by students. Private application documents are specified in `business-registration-workflow`.

## Indexes and queries

- Declare every composite index in `firebase/firestore.indexes.json` together with the code that needs it. Typical: `listings(status, category, createdAt desc)`, `listings(status, priceSen)`, `orders(businessId, status, createdAt desc)`, `businessApplications(status, updatedAt desc)`.
- All list queries use `limit` plus a cursor.

## M4 opportunity engine (deterministic)

Pure functions in `domain/opportunity/` (version constant `ALGO_VERSION`):

1. `normalize(text)`: lowercase, strip punctuation, singularize common plurals, remove stop words, map curated synonyms (`synonyms.ts`, small and reviewed).
2. `clusterKey(category, tokens)`: stable key from the category plus the sorted canonical head term(s).
3. Demand `D` = size of the **union of unique UIDs** (request creators + `requestInterests`) across the cluster.
4. Supply `S` = active, available, non-hidden listings matching the cluster; distinct sellers; median listed price vs median preferred price.
5. `score = max(0, 5*min(D,20) - 8*min(S,10) + (marketMedian > preferredMedian ? 10 : 0))`, ties broken by most recent interest.
6. `reasons[]` are generated from the same numbers (`"7 students interested"`, `"1 active matching listing"`, `"listings are above requested prices"`). If `D < 2`, set `insufficientData: true`.

The trigger recomputes only the affected cluster(s) on request, interest or listing change, plus a scheduled full refresh. It writes `opportunities/{clusterKey}` with `algoVersion`, parameters and `calculatedAt`. Interest toggling uses doc ID `{requestId}_{uid}` so one student counts once.

## Workflow

1. Update `docs/data-dictionary.md` / `docs/api-contracts.md` first.
2. Domain logic with unit tests (`npm --prefix functions run test`).
3. Rules change with allow and deny tests.
4. Service + callable with emulator tests (success, unauthorized, invalid input, invalid transition, and a concurrent race where relevant).
5. Index entries for any new query.
6. `npm --prefix functions run lint && npm --prefix functions run build`, then the emulator test command from CLAUDE.md.

## Verification checklist

- [ ] Handler → guard → zod parse → service; no client-supplied privileged fields are accepted.
- [ ] Conflicting writes are inside a transaction; the audit entry is in the same transaction.
- [ ] Stock never goes below zero; `allocatedQty <= capacity` is enforced in the transaction.
- [ ] Rules are default-deny; each rule change has allow and deny tests.
- [ ] New queries have indexes and pagination.
- [ ] No deploy, no production credentials, no new dependencies without the user's approval.
