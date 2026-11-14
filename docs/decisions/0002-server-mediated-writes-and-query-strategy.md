# 0002: Server-mediated listing writes and query strategy

- **Status:** Superseded by [0003](0003-move-backend-to-supabase.md), which lists what was kept and replaced
- **Date:** 26 Oct 2026

## Context

The handoff requires server-side validation of listing input, rate limits on listings, a normalized product title, a searchable feed, reservation expiry and seller analytics. The original plan let sellers write listings directly to Firestore under Security Rules, and left search, expiry and analytics open. Security Rules can validate field types, but they can't rate-limit, compute derived fields or call shared code. Firestore has no full-text search, and scheduled jobs and third-party search services add cost and moving parts.

## Decisions

1. **Listings are written only through Cloud Functions** (`upsertListing`, `setListingStatus`). Validation, rate limiting, the business-mode check, `normalizedTitle`, `searchTokens` and seller-name snapshots all happen in one tested place, and a listing is never visible before its derived fields exist.
2. **Search uses a `searchTokens` array** built by the same text normalizer that M4 uses, queried with `array-contains` together with category and status filters. No external search service.
3. **Reservations expire lazily.** A `requested` or `accepted` reservation past `expiresAt` is treated as expired wherever it is read or acted on, and is stored as `expired` by the next function that touches it. No scheduled job.
4. **M5 analytics use Firestore aggregation queries** (`count()`, `sum('totalSen')`) over the seller's completed orders filtered by `completedAt`. A `soldQty` counter on each listing, incremented in the order-completion transaction, provides top products.
5. **The admin dashboard imports TypeScript types and zod schemas from `functions/src/domain/`** instead of keeping its own copy. Only the Dart mirror remains.
6. **Feed reads are minimized**: listings store `sellerName` / `businessName` snapshots, and photos are resized on the device (about 1280 px, 80% quality) before upload.

## Consequences

- Two more callables (`upsertListing`, `setListingStatus`). In return there's no listing trigger, no scheduler and no search service, and the Security Rules for `listings` become read-only for clients.
- Search matches whole normalized words, not substrings or typos. That's acceptable for a campus prototype; a search service can replace the token query later without changing the data model much.
- A seller-name snapshot can go stale after a profile rename. It's refreshed the next time the listing is edited, which is acceptable for display purposes.
- Aggregation queries need composite indexes on `orders(businessId, status, completedAt)`.
- Everything here works on the free emulators and needs no extra paid services.
