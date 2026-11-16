# Data dictionary

This is the single definition of CampusNiaga's database (Supabase PostgreSQL) and file storage. It follows the Implementation Handoff v1.0, section 6, adapted to SQL by [ADR 0003](decisions/0003-move-backend-to-supabase.md).

The tables themselves are defined in `supabase/migrations/`. A table marked ✅ exists; the others are planned and are created by their phase's migration. Any change to a table updates this document and adds a migration in the same commit. The Flutter app mirrors status values in `mobile/lib/core/domain/`; the admin dashboard uses types generated from the database.

## Conventions

| Rule | Detail |
|---|---|
| Names | Tables plural, columns `snake_case` |
| Keys | `id uuid` (or `bigint` identity for logs); foreign keys reference the parent's `id` |
| Status values | `snake_case` text with a `check` constraint, exactly as listed here |
| Money | Integer **sen** (`price_sen`, `total_sen`): RM 12.50 is stored as `1250`. Never floating-point RM |
| Time | `timestamptz`. Every table has `created_at`, and changeable tables have `updated_at`, kept by a trigger |
| Owner columns | `owner_id`, `applicant_id`, `buyer_id`, `creator_id`, `reporter_id` can't change after creation |
| Written by | **Client**: the app may write it directly, as Row Level Security and column privileges allow. **Server**: only database functions write it. **Input**: supplied by the user, validated and written by a database function |
| Access | Row Level Security is on for every table. Without a matching policy, access is denied |

## Who is what

Roles are read from tables on every request, never from login tokens:

| Role | Rule (database function) |
|---|---|
| Verified student | `is_student()`: email confirmed, address matches `app_config.student_email_domains` exactly or is in `app_config.test_allowlist`, and the profile is `active` |
| Reviewer | `is_reviewer()`: a `staff_roles` row with `role = 'reviewer'` |
| Admin | `is_admin()`: a `staff_roles` row with `role = 'admin'` |
| Approved business owner | `owns_business(business_id)`: a verified student who owns that `businesses` row and its `status` is `approved` (Phase 3 ✅) |

## Tables

### `auth.users` (managed by Supabase Auth)

Accounts, passwords, emails and email confirmation (`email_confirmed_at`). The apps never write it directly; Supabase Auth does.

### `profiles` (Phase 1 ✅)

One per account, created by a trigger when someone signs up.

| Column | Type | Written by | Notes |
|---|---|---|---|
| `id` | uuid | Server | Same as `auth.users.id` |
| `name` | text | Client | 1–60 characters, not only spaces. The only column a user may change, and only while `active`. Defaults to the sign-up name, else the part of the email before the @ |
| `email` | text | Server | Copied from Auth, and kept in sync when it changes |
| `account_status` | `active` \| `suspended` | Server | Suspended accounts lose student access |

Read: the owner, and admins.

### `staff_roles` (Phase 1 ✅)

| Column | Type | Notes |
|---|---|---|
| `user_id` | uuid | Primary key together with `role` |
| `role` | `reviewer` \| `admin` | |
| `granted_by` | uuid? | The admin who granted it |
| `created_at` | timestamptz | |

Written only by `set_staff_role()`. Read: the user's own rows, and admins. The first admin is added in the Supabase SQL editor (see the README).

### `app_config` (Phase 1 ✅)

A single row of settings. Read by admins only, because it holds the test allowlist. Changed in the Supabase dashboard, never from the apps.

| Column | Type | Default |
|---|---|---|
| `student_email_domains` | text[] | `{student.usm.my}`, at least one |
| `test_allowlist` | text[] | empty. Emails allowed for FYP evaluation |
| `categories` | text[] | Books, Electronics, Fashion, Food & Beverage, Hostel Essentials, Stationery, Others |
| `max_application_documents` | integer | 5 |
| `max_upload_bytes` | integer | 5,242,880 (5 MB) |

### `audit_logs` (Phase 1 ✅)

Append-only record of important actions, written only by database functions. Read: admins. Reviewers see an application's changes through `application_status_history` instead.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | Identity |
| `actor_id` | uuid? | Who did it |
| `action` | text | e.g. `role.granted`, `application.approved`, `listing.hidden` |
| `target_type`, `target_id` | text | e.g. `user` / the user's id |
| `metadata` | jsonb | Minimal context only; no sensitive data |
| `created_at` | timestamptz | |

### `listings` (Phase 2 ✅)

A product, shared by personal sellers and approved businesses. Written only through `upsert_listing()` and `set_listing_status()`; orders (Phase 4) change `stock` and `status` of business listings. Owners and admins read the table directly; other students see listings through `search_listings()`, `get_listing()` and `get_storefront()`, which add the seller's name (and the business name for business products) and leave out drafts, hidden listings, suspended sellers and suspended businesses.

**Personal items are reserved; business products are ordered.** A `personal` listing is bought through a reservation (M1); a `business` listing through an order (M3). Each function refuses the other kind.

| Column | Type | Source | Notes |
|---|---|---|---|
| `id` | uuid | Server | |
| `owner_id` | uuid | Server | The caller; can't change |
| `mode` | `personal` \| `business` | Input (create only) | `business` requires an approved business owned by the caller (`owns_business`); editing a business listing needs it too, so a suspended business can't change its catalogue |
| `business_id` | uuid? | Server | Set for `business` mode |
| `title` | text | Input | 3–80 characters |
| `normalized_title` | text | Server | Lowercased, punctuation removed; used by M4 matching |
| `search_vector` | tsvector | Server | Generated from title (weight A), description (B) and category (C) with the `english` configuration; GIN index |
| `description` | text | Input | Up to 1,000 characters |
| `category` | text | Input | One of `app_config.categories` |
| `price_sen` | integer | Input | 0–10,000,000 |
| `condition` | `new` \| `like_new` \| `good` \| `fair` | Input | |
| `photo_paths` | text[] | Input | Up to 5 paths `{owner_id}/{listing_id}/{file}` in the `listing-photos` bucket (resized on the device before upload). At least 1 once the listing leaves `draft` |
| `stock` | integer | Input (`quantity`, 1–999) + Server | Units still for sale. Reservations (personal) and ready-stock orders (business) take units out under a row lock when they are made; cancelled, declined or expired ones put them back. Never negative; at least 1 while `available`, 0 when `sold`. A business owner restocks by editing the quantity, which also makes a sold-out (`sold`) business listing `available` again |
| `pickup_area` | text | Input | Campus pickup location |
| `status` | `draft` \| `available` \| `reserved` \| `sold` \| `closed` | Server | `draft` → `available` → `reserved` (every remaining unit is held by accepted reservations) → `sold` (all collected); `closed` when withdrawn (it can re-open); `available` → `sold` directly when sold outside the app. A cancelled or expired reservation returns it to `available` |
| `hidden` | boolean | Server | Admin moderation; hidden listings are left out of feeds and M4 supply |
| `created_at`, `updated_at` | timestamptz | Server | |

Indexes: full-text (`search_vector`), feed (`status, category, price_sen` where not hidden), owner (`owner_id, status, created_at`).

### `reservations` (Phase 2 ✅)

Written only by `request_reservation()` and `resolve_reservation()`. The buyer and the seller read their own; admins read all. Only `personal` listings can be reserved (a trigger refuses business listings).

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `listing_id`, `buyer_id`, `seller_id` | uuid | The buyer can't be the seller |
| `qty` | integer | Units reserved, 1–999 and no more than the listing's stock at the time |
| `pickup_note` | text? | Buyer's preferred time or place, up to 200 characters |
| `status` | `requested` \| `accepted` \| `declined` \| `cancelled` \| `collected` \| `expired` | `requested` → `accepted` (seller) → `collected` (seller). `requested` → `declined` (seller). `requested`/`accepted` → `cancelled` (either side) or `expired` |
| `expires_at` | timestamptz? | Set while `requested` (48 hours to answer) or `accepted` (7 days to collect); cleared otherwise |
| `created_at`, `updated_at` | timestamptz | |

**Units are held from the moment of the request.** `request_reservation()` locks the listing row, checks `stock` and takes the units out in one transaction, so two buyers asking for the last unit at the same moment can't both get it: the second waits for the lock, then gets `ITEM_UNAVAILABLE`. Declining, cancelling or expiring returns the units; collecting keeps them gone, and the listing becomes `sold` when no stock and no active reservation remain. A buyer has at most one active (`requested` or `accepted`) reservation per listing (`ALREADY_EXISTS`, plus a partial unique index). A listing with active reservations can't be closed or marked sold.

**Expiry is lazy:** overdue reservations become `expired` (and return their units) when a reservation on the same listing is requested or resolved, when the listing's status is changed, or when the buyer or seller opens My Reservations. There is no scheduled job.

### `business_applications` (Phase 3 ✅)

A student's request to run a business on CampusNiaga (M2). The approval is a **simulated** reviewer workflow for the FYP, not an official USM decision. The applicant inserts a draft and edits its content directly; every status change goes through `submit_business_application()` or `review_business_application()`.

| Column | Type | Written by | Notes |
|---|---|---|---|
| `id` | uuid | Server | |
| `applicant_id` | uuid | Server | The caller (column default `auth.uid()`); can't change |
| `business_name` | text | Client | Up to 80 characters; 3–80 to submit |
| `category` | text | Client | One of `app_config.categories` to submit |
| `description` | text | Client | Up to 1,000 characters; at least 20 to submit |
| `contact_details` | text | Client | How buyers reach the business (phone, Instagram); up to 200, at least 5 to submit |
| `collection_details` | text | Client | Where and when buyers collect; up to 200, at least 5 to submit. Becomes the business's `pickup_details` |
| `document_paths` | text[] | Client | Uploaded files `{applicant_id}/{application_id}/{file}` in `application-documents` (PDF, JPEG or PNG). Optional; up to `app_config.max_application_documents`, each one must exist to submit |
| `status` | `draft` \| `submitted` \| `under_review` \| `info_requested` \| `approved` \| `rejected` | Client (`draft` on insert) / Server | See the state machine below |
| `reviewer_id` | uuid? | Server | The staff member who last acted on it |
| `remarks` | text? | Server | The latest reviewer note |
| `submitted_at` | timestamptz? | Server | Last (re)submission; the review queue is ordered by it, oldest first |
| `decided_at` | timestamptz? | Server | Set on approval or rejection |
| `created_at`, `updated_at` | timestamptz | Server | |

**State machine** (enforced in the functions; any other change fails with `INVALID_TRANSITION`):

| From | To | Who | How |
|---|---|---|---|
| (new) | `draft` | Applicant (verified student) | Direct insert |
| `draft` / `info_requested` | `submitted` | Applicant | `submit_business_application` |
| `submitted` | `under_review` | Reviewer or admin | `review_business_application(…, 'start_review')` |
| `under_review` | `info_requested` | Reviewer or admin | `… 'request_info'`, with a note |
| `under_review` | `approved` | Reviewer or admin | `… 'approve'`; creates the business |
| `under_review` | `rejected` | Reviewer or admin | `… 'reject'`, with a note |

`approved` and `rejected` are final. The content columns can be changed only while `draft` or `info_requested`; `status`, `reviewer_id`, `remarks` and the dates never by the client (column privileges). A student has **at most one unfinished application** (any status except `approved` and `rejected`, drafts included) and at most one business, so a rejected applicant may apply again but an approved one doesn't need to. Staff can't review their own application.

Read: the applicant; reviewers and admins once it has left `draft` (drafts stay private). Reviewers may also read the name and email of a student whose application they can see.

### `application_status_history` (Phase 3 ✅)

Append-only, one row per status change, written in the same transaction as the change. Nobody can edit or delete it. Read by whoever can read the application.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | Identity |
| `application_id` | uuid | |
| `from_status`, `to_status` | text | Application statuses |
| `actor_id` | uuid? | Who made the change |
| `actor_role` | `applicant` \| `reviewer` \| `admin` | |
| `note` | text? | The reviewer's note, or the applicant's reply when resubmitting |
| `created_at` | timestamptz | |

### `businesses` (Phase 3 ✅)

Created only by `review_business_application(…, 'approve')`, in the same transaction as the approval. Read: the owner, reviewers and admins directly; other students see an approved business's storefront through `get_storefront()`. The owner changes the storefront (description, pickup details, logo) through `update_storefront()`. No client writes.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `owner_id` | uuid | The applicant; one business per student |
| `application_id` | uuid | The approved application; unique |
| `name`, `description` | text | From the application; the owner may edit the description |
| `logo_path` | text? | `{business_id}/{file}` in `business-logos`, set by `update_storefront()` |
| `pickup_details` | text | From the application's `collection_details`; the owner may edit it. Copied into each ready-stock order |
| `status` | `approved` \| `suspended` | Changed only by `set_business_status()` (admins). A suspended business loses business access at once |
| `created_at`, `updated_at` | timestamptz | |

`listings.business_id` references this table.

### `campaigns` (Phase 4 ✅)

A pre-order campaign for one business product. Written only by `upsert_campaign()`, `set_campaign_status()` and, for `allocated_qty`, `place_order()` / `transition_order()`. Read: the business owner and admins directly; other students see open campaigns of approved businesses through `get_storefront()`.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `business_id` | uuid | Server: the listing's business |
| `listing_id` | uuid | Input (create only): a published business listing of the caller's business |
| `title` | text | 3–80 characters |
| `price_sen` | integer | 0–10,000,000. The pre-order price; orders copy it |
| `start_at`, `close_at` | timestamptz | `close_at` after `start_at`, and in the future when created or opened. Orders are taken only between them |
| `capacity` | integer | 1–10,000: the most units the business can fulfil. Can't be lowered below `allocated_qty` |
| `per_order_limit` | integer? | 1 to `capacity`; no limit when empty |
| `allocated_qty` | integer | Server. Units held by orders that aren't cancelled. Never above `capacity` (check constraint); changed only under the campaign's row lock |
| `pickup_details` | text | 5–200 characters. Copied into each pre-order |
| `status` | `draft` \| `open` \| `closed` | `draft` → `open` → `closed`, or `draft` → `closed`. Only `open` campaigns inside their dates take orders; closing keeps existing orders |
| `created_at`, `updated_at` | timestamptz | |

### `orders` (Phase 4 ✅)

An order for a business product: ready stock (no campaign) or a pre-order (with a campaign). Written only by `place_order()` and `transition_order()`. Read: the buyer, the business owner (also while the business is suspended) and admins; the apps use `my_orders()`, which adds names and, once confirmed, contact emails.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `buyer_id` | uuid | The caller; never the business owner |
| `business_id`, `listing_id` | uuid | From the listing |
| `campaign_id` | uuid? | Present for pre-orders |
| `qty` | integer | 1–999, and within the campaign's `per_order_limit` |
| `unit_price_sen` | integer | Price snapshot at order time (the listing's, or the campaign's for a pre-order); later price changes don't touch it |
| `total_sen` | bigint | `unit_price_sen × qty` (check constraint) |
| `status` | `pending_confirmation` \| `confirmed` \| `preparing` \| `ready_for_pickup` \| `completed` \| `cancelled` | The seller moves it forward one step at a time; either side may cancel before `completed` |
| `buyer_note` | text? | The buyer's collection preference, up to 200 characters |
| `collection_details` | text | Snapshot of where and when to collect: the campaign's `pickup_details` for a pre-order, otherwise the business's |
| `cancelled_by` | `buyer` \| `seller`? | Set exactly when `cancelled`. A seller cancelling a pending order is a rejection |
| `cost_sen` | integer? | Seller-entered cost, for estimated profit (written from Phase 6) |
| `completed_at` | timestamptz? | Set exactly when `completed`; M5 date filters and totals |
| `created_at`, `updated_at` | timestamptz | |

**Quantity is held from the moment of ordering.** `place_order()` locks the listing (ready stock) or the campaign (pre-order), checks what is left and takes it in one transaction, so two buyers can never get more than exists: the second waits for the lock, then gets `ITEM_UNAVAILABLE` or `CAPACITY_FULL`. A ready-stock order takes units out of `listings.stock` (the listing becomes `sold` at 0); a pre-order adds to `campaigns.allocated_qty` and doesn't touch the listing's stock. Cancelling returns them; progressing and completing keep them (capacity is a fulfilment limit, so a completed pre-order still counts). No payment happens in the app: buyer and seller arrange payment and collection themselves.

### `product_requests` (Phase 5)

`id`, `creator_id`, `name`, `normalized_name`, `category`, `preferred_price_sen?`, `campus_area`, `notes?`, `cluster_key?` (server), `status` (`active` \| `closed`).

### `request_interests` (Phase 5)

`request_id`, `user_id`, `created_at`. The primary key `(request_id, user_id)` allows one interest per student per request.

### `opportunities` (Phase 5)

Derived M4 result per cluster, written only by the server: `cluster_key` (primary key), `category`, `keywords[]`, `request_ids[]`, `unique_interest_count`, `active_supply_count`, `distinct_seller_count`, `median_listed_price_sen?`, `median_preferred_price_sen?`, `price_gap`, `score`, `reasons[]`, `insufficient_data` (fewer than 2 students), `algo_version`, `calculated_at`.

### `reports` (Phase 2 ✅)

Written only by `report_listing()` (students) and the admin functions. Reporters read their own; admins read all. Never deleted.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `reporter_id` | uuid | The student who reported |
| `listing_id` | uuid? | The reported listing |
| `reported_user_id` | uuid? | The listing's owner at the time |
| `reason` | `prohibited_item` \| `scam` \| `offensive` \| `misleading` \| `other` | `other` needs details |
| `details` | text | Up to 500 characters |
| `status` | `open` \| `reviewed` \| `actioned` | `reviewed`: dismissed. `actioned`: the listing was hidden or the account suspended |
| `action` | `dismissed` \| `listing_hidden` \| `account_suspended`? | Set exactly when the report is closed |
| `reviewed_by`, `reviewed_at`, `review_note` | | The admin's decision |
| `created_at`, `updated_at` | timestamptz | |

One open report per student per listing. Students may send 10 reports a day.

### `notifications` (Phase 2 ✅)

In-app notices written by database functions. The recipient reads their own and may set `read`; nothing else is writable.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | |
| `recipient_id` | uuid | |
| `type` | text | `order_placed`, `order_confirmed`, `order_preparing`, `order_ready_for_pickup`, `order_completed`, `order_cancelled`, `reservation_requested`, `reservation_accepted`, `reservation_declined`, `reservation_cancelled`, `reservation_collected`, `reservation_expired`, `listing_hidden`, `listing_restored`, `application_under_review`, `application_info_requested`, `application_approved`, `application_rejected`, `business_suspended`, `business_reinstated`; later phases add more |
| `target` | text? | What it's about, e.g. `reservation:{id}`, `listing:{id}`, `application:{id}`, `business:{id}` or `order:{id}` |
| `title`, `body` | text | |
| `read` | boolean | |
| `created_at` | timestamptz | |

## File storage (Supabase Storage buckets)

| Bucket | Contents | Access |
|---|---|---|
| `listing-photos` (Phase 2) | Product photos: JPEG, PNG or WebP, up to 5 MB, under `{owner_id}/{listing_id}/` | Private bucket. A verified student uploads only into a folder of a listing they own (`can_upload_listing_photo`) and deletes only their own files; verified students and admins read, with their sign-in token |
| `application-documents` (Phase 3) | Business application documents: PDF, JPEG or PNG, up to 5 MB, under `{applicant_id}/{application_id}/` | Private. The applicant uploads and deletes only while their application is `draft` or `info_requested`, up to `app_config.max_application_documents` files (`can_upload_application_document`); files are never overwritten. The applicant, and reviewers and admins once it is submitted, read through short-lived signed URLs (`can_read_application_document`) |
| `business-logos` (Phase 4) | Business logos: JPEG, PNG or WebP, up to 2 MB, under `{business_id}/` | Private bucket. The owner of an approved business uploads into its folder (`can_upload_business_logo`) and deletes its own files; verified students and staff read with their sign-in token |
