# Data dictionary

This is the single definition of CampusNiaga's Cloud Firestore and Cloud Storage data. It follows the Implementation Handoff v1.0, section 6.

Each codebase mirrors these definitions in exactly one file:

| Codebase | Definition |
|---|---|
| Cloud Functions | `functions/src/domain/types.ts` (the TypeScript source of truth) |
| Admin dashboard | Imports the Functions file directly (type-only imports), so there is no separate copy |
| Mobile app | `mobile/lib/core/domain/` (Dart mirror) |

Any change to this document must update the Functions types and the Dart mirror in the same commit.

## Conventions

| Rule | Detail |
|---|---|
| Field names | `camelCase` |
| Collection names | `camelCase`, plural |
| Status values | `snake_case` strings, exactly as listed here |
| Money | Integer **sen** (RM 12.50 is stored as `1250`). Never floating-point RM |
| Time | Firestore `Timestamp`, written with server timestamps |
| Common fields | Every document has `createdAt` and `updatedAt` |
| Owner fields | `ownerUid`, `applicantUid`, `buyerUid`, `creatorUid` and `reporterUid` cannot change after creation |
| Written by | **Client**: the app may write it directly, as limited by Security Rules. **Server**: only Cloud Functions write it. **Input**: supplied by the user but validated and written by a Cloud Function |

Optional fields are marked with `?`.

## Collections

### `users/{uid}`

A user profile, created by the server at first sign-in.

| Field | Type | Written by | Notes |
|---|---|---|---|
| `name` | string | Client | Display name |
| `email` | string | Server | Copied from Firebase Auth |
| `verified` | boolean | Server | Verified USM student (mirrors the `student` claim) |
| `roleFlags` | map `{ student, business, reviewer, admin }` of booleans | Server | **Display only.** Access is decided by custom claims, never by this field |
| `accountStatus` | `active` \| `suspended` | Server | |

### `listings/{listingId}`

A product, shared by personal sellers and approved businesses. All listing writes go through the `upsertListing` and `setListingStatus` functions ([ADR 0002](decisions/0002-server-mediated-writes-and-query-strategy.md)), so every field is server-written; "Input" marks fields the seller supplies.

| Field | Type | Source | Notes |
|---|---|---|---|
| `ownerUid` | string | Server | The caller's UID; can't change |
| `mode` | `personal` \| `business` | Input (create only) | `business` requires the caller's `businessId` claim |
| `businessId?` | string | Server | Taken from the caller's claim when `mode == business` |
| `sellerName` | string | Server | Snapshot of the seller's display name, so feed cards need no extra read |
| `businessName?` | string | Server | Snapshot of the business name for business listings |
| `title` | string | Input | 3–80 characters |
| `normalizedTitle` | string | Server | Lowercased, punctuation removed; used for M4 matching |
| `searchTokens` | string[] | Server | Normalized words of title and category; queried with `array-contains` |
| `description` | string | Input | Up to 1,000 characters |
| `category` | string | Input | One of the configured categories |
| `priceSen` | integer | Input | 0–10,000,000 |
| `condition` | `new` \| `like_new` \| `good` \| `fair` | Input | |
| `photoPaths` | string[] | Input | Storage paths under the caller's folder, 1–5 photos (resized on the device before upload) |
| `stock` | integer | Input (personal) / Server (business orders) | 0 or more; personal items are usually 1 |
| `soldQty` | integer | Server | Incremented when an order completes; used for M5 top products |
| `pickupArea` | string | Input | Campus pickup location |
| `status` | see below | Server | |
| `hidden` | boolean | Server | Set by admin moderation; hidden listings are excluded from feeds and M4 supply counts |

**Listing status:** `draft` → `available` → `reserved` → `sold`. Also `closed` (the seller withdrew it). A seller may return a `reserved` listing to `available` when its reservation is cancelled or expires.

### `reservations/{reservationId}`

A buyer's request for a personal listing.

| Field | Type | Written by | Notes |
|---|---|---|---|
| `listingId` | string | Server | |
| `buyerUid` | string | Server | Cannot be the seller |
| `sellerUid` | string | Server | Copied from the listing |
| `pickupNote?` | string | Server | Buyer's preferred pickup time or place |
| `status` | `requested` \| `accepted` \| `declined` \| `cancelled` \| `collected` \| `expired` | Server | |
| `expiresAt?` | Timestamp | Server | |

Only one accepted active reservation may exist per personal listing.

Expiry is evaluated when a reservation is read or acted on: a `requested` or `accepted` reservation whose `expiresAt` has passed is treated as `expired`, and the next function that touches it stores that status. There is no scheduled expiry job.

### `businessApplications/{applicationId}`

A student's application to become an approved business (M2).

| Field | Type | Written by | Notes |
|---|---|---|---|
| `applicantUid` | string | Client (create) | Can't change |
| `businessName` | string | Client | Editable only while `draft` or `info_requested` |
| `category` | string | Client | Same rule |
| `description` | string | Client | Same rule |
| `contactDetails` | string | Client | Same rule |
| `collectionDetails` | string | Client | Same rule |
| `documentPaths` | string[] | Client | Private Storage paths; same rule |
| `status` | `draft` \| `submitted` \| `under_review` \| `info_requested` \| `approved` \| `rejected` | Client (`draft` only) / Server | |
| `reviewerUid?` | string | Server | |
| `remarks?` | string | Server | Latest reviewer note |
| `statusHistory` | array of `{ from, to, byUid, role, note?, at }` | Server | Append-only |
| `submittedAt?` | Timestamp | Server | |
| `decidedAt?` | Timestamp | Server | |

### `businesses/{businessId}`

An approved student business. Created only when a reviewer approves an application.

| Field | Type | Written by | Notes |
|---|---|---|---|
| `ownerUid` | string | Server | |
| `applicationId` | string | Server | |
| `name` | string | Server | |
| `description` | string | Server | |
| `logoPath?` | string | Server | |
| `pickupDetails` | string | Server | |
| `status` | `approved` \| `suspended` | Server | |

### `campaigns/{campaignId}`

A pre-order campaign for a business product (M3).

| Field | Type | Written by | Notes |
|---|---|---|---|
| `businessId` | string | Server | |
| `listingId` | string | Server | A `mode == business` listing of the same business |
| `title` | string | Server | |
| `priceSen` | integer | Server | |
| `startAt` | Timestamp | Server | |
| `closeAt` | Timestamp | Server | Must be after `startAt` |
| `capacity` | integer | Server | Maximum quantity that can be fulfilled |
| `perOrderLimit?` | integer | Server | |
| `allocatedQty` | integer | Server | Never exceeds `capacity`; changed only inside transactions |
| `pickupDetails` | string | Server | |
| `status` | `draft` \| `open` \| `closed` | Server | |

### `orders/{orderId}`

A buyer's order from an approved business: ready stock or pre-order.

| Field | Type | Written by | Notes |
|---|---|---|---|
| `buyerUid` | string | Server | |
| `businessId` | string | Server | |
| `listingId` | string | Server | |
| `campaignId?` | string | Server | Present for pre-orders |
| `qty` | integer | Server | 1 or more |
| `unitPriceSen` | integer | Server | Price snapshot at order time |
| `totalSen` | integer | Server | `unitPriceSen × qty` |
| `status` | `pending_confirmation` \| `confirmed` \| `preparing` \| `ready_for_pickup` \| `completed` \| `cancelled` | Server | |
| `collectionDetails` | string | Server | |
| `costSen?` | integer | Server | Seller-entered cost, used for estimated profit (M5) |
| `completedAt?` | Timestamp | Server | Set when the order completes; M5 date filters and `sum()`/`count()` aggregation queries use it |

**Order status:** `pending_confirmation` → `confirmed` → `preparing` → `ready_for_pickup` → `completed`. Can move to `cancelled` from any state before `completed`. Pending and confirmed orders reserve campaign capacity; cancellation releases it.

### `productRequests/{requestId}`

A student's request for a product that isn't available (M4).

| Field | Type | Written by | Notes |
|---|---|---|---|
| `creatorUid` | string | Client (create) | |
| `name` | string | Client | |
| `normalizedName` | string | Server | |
| `category` | string | Client | |
| `preferredPriceSen?` | integer | Client | |
| `campusArea` | string | Client | |
| `notes?` | string | Client | |
| `clusterKey?` | string | Server | The opportunity cluster this request belongs to |
| `status` | `active` \| `closed` | Client (own) / Server | |

### `requestInterests/{requestId}_{uid}`

One student's interest in a product request. The deterministic document ID makes it one interest per student per request.

| Field | Type | Written by | Notes |
|---|---|---|---|
| `requestId` | string | Server | |
| `uid` | string | Server | |

### `opportunities/{clusterKey}`

Derived M4 result for a group of similar requests. Recomputed by the server only.

| Field | Type | Notes |
|---|---|---|
| `category` | string | |
| `keywords` | string[] | Canonical terms of the cluster |
| `requestIds` | string[] | |
| `uniqueInterestCount` | integer | Distinct students (request creators and interests combined) |
| `activeSupplyCount` | integer | Matching available, non-hidden listings |
| `distinctSellerCount` | integer | |
| `medianListedPriceSen?` | integer | |
| `medianPreferredPriceSen?` | integer | |
| `priceGapFlag` | boolean | Market median is above requesters' preferred median |
| `score` | integer | |
| `reasons` | string[] | Human-readable explanations generated from the numbers above |
| `insufficientData` | boolean | `true` when fewer than 2 students are interested |
| `algoVersion` | string | Version of the ranking rules used |
| `calculatedAt` | Timestamp | |

### `reports/{reportId}`

A user's report of an inappropriate listing or user.

| Field | Type | Written by | Notes |
|---|---|---|---|
| `reporterUid` | string | Client (create) | |
| `listingId?` | string | Client (create) | |
| `reportedUid?` | string | Client (create) | |
| `reason` | string | Client (create) | |
| `status` | `open` \| `reviewed` \| `actioned` | Server | |
| `action?` | string | Server | What the admin did |

### `auditLogs/{logId}`

Append-only record of important actions. Written only by the server.

| Field | Type | Notes |
|---|---|---|
| `actorUid` | string | |
| `action` | string | e.g. `application.approved`, `role.granted`, `listing.hidden` |
| `targetType` | string | e.g. `businessApplication`, `user`, `listing` |
| `targetId` | string | |
| `at` | Timestamp | |
| `metadata?` | map | Minimal context only; no sensitive data |

### `notifications/{notificationId}`

In-app notices (decisions, reservations, order changes). Written by the server; the recipient may mark them read.

| Field | Type | Written by | Notes |
|---|---|---|---|
| `recipientUid` | string | Server | |
| `type` | string | Server | e.g. `application_decision`, `reservation_update`, `order_update` |
| `title` | string | Server | |
| `body` | string | Server | |
| `targetPath?` | string | Server | Document path to open |
| `read` | boolean | Client (recipient) | |

### `config/app`

App settings. Readable by admins only; read by Cloud Functions.

| Field | Type | Notes |
|---|---|---|
| `studentEmailDomains` | string[] | Default `["student.usm.my"]` |
| `testAllowlist` | string[] | Emails allowed for FYP evaluation |
| `categories` | string[] | Product categories |
| `maxApplicationDocuments` | integer | Default 5 |
| `maxUploadBytes` | integer | Default 5,242,880 (5 MB) |

## Custom claims

Access decisions use Firebase Auth custom claims, set only by Cloud Functions or the seed script.

| Claim | Type | Meaning |
|---|---|---|
| `student` | boolean | Verified USM student (or allowlisted test account) |
| `reviewer` | boolean | Prototype university reviewer (web dashboard) |
| `admin` | boolean | System administrator (web dashboard) |
| `businessId` | string | ID of the user's approved, active business |

## Cloud Storage paths

| Path | Contents | Access |
|---|---|---|
| `listings/{uid}/{listingId}/{fileName}` | Product photos: JPEG, PNG or WebP, up to 5 MB | Owner writes; verified students read |
| `applications/{applicantUid}/{applicationId}/{fileName}` | Business application documents: PDF, JPEG or PNG, up to 5 MB | Applicant writes while the application is editable; applicant and reviewers read; never public |
| `businesses/{businessId}/logo/{fileName}` | Business logo | Business owner writes; verified students read |
