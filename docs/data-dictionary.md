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
| HDC administrator | `is_admin()`: a `staff_roles` row with `role = 'admin'`. The one staff role ([ADR 0009](decisions/0009-single-admin-role.md)): administrators review business applications and run the platform. `is_staff()` means the same |
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
| `role` | `admin` | The HDC administrator, the only staff role. `reviewer` existed until [ADR 0009](decisions/0009-single-admin-role.md); the migration made every reviewer an administrator |
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

Append-only record of important actions, written only by database functions. Read: admins.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | Identity |
| `actor_id` | uuid? | Who did it |
| `action` | text | e.g. `role.granted`, `application.approved`, `listing.hidden` |
| `target_type`, `target_id` | text | e.g. `user` / the user's id |
| `metadata` | jsonb | Minimal context only; no sensitive data |
| `created_at` | timestamptz | |

### `listings` (Phase 2 ✅)

A product, shared by personal sellers and approved businesses. Written only through `upsert_listing()` and `set_listing_status()`; purchases (personal) and orders (business) change `stock` and `status`. Owners and admins read the table directly; other students see listings through `search_listings()`, `get_listing()` and `get_storefront()`, which add the seller's name (and the business name for business products) and leave out drafts, hidden listings, suspended sellers and suspended businesses.

**Personal items are bought with Buy now; business products are ordered.** A `personal` listing is bought through a purchase (M1, [ADR 0006](decisions/0006-buy-now.md)); a `business` listing through an order (M3). Each function refuses the other kind.

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
| `photo_paths` | text[] | Input | Up to 5 paths `{owner_id}/{listing_id}/{file}` in the `listing-photos` bucket (resized on the device before upload). At least 1 unless `draft` or `deleted` |
| `stock` | integer | Input (`quantity`, 1–999) + Server | Units still for sale. Purchases (personal) and ready-stock orders (business) take units out under a row lock when they are made; cancelled ones put them back. Never negative; at least 1 while `available`, 0 when `sold`. A business owner restocks by editing the quantity, which also makes a sold-out (`sold`) business listing `available` again |
| `pickup_area` | text | Input | Campus pickup location |
| `pickup_lat`, `pickup_lng` | double precision? | Input | Optional map pin, in degrees (WGS 84): both or neither, inside Malaysia's bounding box (latitude 0.8–7.5, longitude 99.5–119.5). Shown to everyone who can see the listing ([pickup pins](#pickup-pins)) |
| `status` | `draft` \| `available` \| `sold` \| `closed` \| `deleted` | Server | `draft` → `available` → `sold` (no units left: bought, ordered, or marked sold outside the app). Any status but `deleted` → `deleted` by the owner ([ADR 0008](decisions/0008-listing-payment-and-delete.md)): final, out of every list, kept for the purchases, orders, chats and reports that point at it, and still shown to its owner, admins and a student who bought it. `closed` is from before ADR 0008: such a listing can be re-opened or deleted, but nothing is closed any more. A cancelled purchase makes a sold listing `available` again and never revives a deleted one |
| `hidden` | boolean | Server | Admin moderation; hidden listings are left out of feeds and M4 supply |
| `created_at`, `updated_at` | timestamptz | Server | |

Indexes: full-text (`search_vector`), feed (`status, category, price_sen` where not hidden), owner (`owner_id, status, created_at`).

### `purchases` (M1, [ADR 0006](decisions/0006-buy-now.md))

A personal item bought with Buy now. Written only by `buy_item()`, `complete_purchase()`, `cancel_purchase()`, `relist_purchase()` and the payment functions. The buyer and the seller read their own; admins read all. Business listings are refused (they are ordered).

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `listing_id`, `buyer_id`, `seller_id` | uuid | The buyer can't be the seller |
| `qty` | integer | 1–999 and no more than the stock at the time |
| `unit_price_sen` | integer | The price at the moment of buying |
| `total_sen` | bigint | `unit_price_sen × qty` (check constraint) |
| `payment_method` | `cash` \| `transfer` | |
| `status` | `awaiting_payment` \| `awaiting_handover` \| `completed` \| `cancelled` | Cash starts at `awaiting_handover`; transfer at `awaiting_payment` until the seller accepts the payment. `awaiting_handover` → `completed` (seller). Either awaiting status → `cancelled` |
| `cancelled_by` | `buyer` \| `seller` \| `system`? | Only when cancelled. `system`: no receipt within 30 minutes. Empty for converted reservations that didn't record who cancelled |
| `cancel_reason` | text? | 1–200 characters, only when cancelled. Required from a seller |
| `completed_at` | timestamptz? | Set exactly when `completed` |
| `created_at`, `updated_at` | timestamptz | |

**Units are the buyer's from Confirm purchase.** `buy_item()` locks the listing row, checks `stock` and takes the units out in one transaction: first come, first served. A buyer has at most one unfinished purchase per listing (`ALREADY_EXISTS`, plus a partial unique index), 3 unfinished cash purchases and 10 purchases an hour (`RATE_LIMITED`). A seller may close a listing with purchases in progress; only the units still for sale are withdrawn.

**What releases units:** the buyer cancels (not after sending a receipt); the seller cancels with a reason (relist, or delete the listing) or relists uncollected cash 24 hours after the purchase; the seller rejects a receipt; or a transfer has no receipt 30 minutes after buying. Only the last happens automatically: it is lazy, when the listing is next locked to change or a read function sweeps. Cash, and a transfer with a receipt, are never released automatically.

The reservations that purchases replaced are kept as they were in `legacy.reservations`, a schema the API doesn't expose and no app role can use.

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
| `admin_id` | uuid? | Server | The HDC administrator who last acted on it (`reviewer_id` until migration `20261123000400`, [ADR 0009](decisions/0009-single-admin-role.md)) |
| `remarks` | text? | Server | The administrator's latest note |
| `submitted_at` | timestamptz? | Server | Last (re)submission; the review queue is ordered by it, oldest first |
| `decided_at` | timestamptz? | Server | Set on approval or rejection |
| `created_at`, `updated_at` | timestamptz | Server | |

**State machine** (enforced in the functions; any other change fails with `INVALID_TRANSITION`):

| From | To | Who | How |
|---|---|---|---|
| (new) | `draft` | Applicant (verified student) | Direct insert |
| `draft` / `info_requested` | `submitted` | Applicant | `submit_business_application` |
| `submitted` | `under_review` | Administrator | `review_business_application(…, 'start_review')` |
| `under_review` | `info_requested` | Administrator | `… 'request_info'`, with a note |
| `under_review` | `approved` | Administrator | `… 'approve'`; creates the business |
| `under_review` | `rejected` | Administrator | `… 'reject'`, with a note |

`approved` and `rejected` are final. The content columns can be changed only while `draft` or `info_requested`; `status`, `admin_id`, `remarks` and the dates never by the client (column privileges). A student has **at most one unfinished application** (any status except `approved` and `rejected`, drafts included) and at most one business, so a rejected applicant may apply again but an approved one doesn't need to. Staff can't review their own application.

Read: the applicant; administrators once it has left `draft` (drafts stay private).

### `application_status_history` (Phase 3 ✅)

Append-only, one row per status change, written in the same transaction as the change. Nobody can edit or delete it. Read by whoever can read the application.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | Identity |
| `application_id` | uuid | |
| `from_status`, `to_status` | text | Application statuses |
| `actor_id` | uuid? | Who made the change |
| `actor_role` | `applicant` \| `reviewer` \| `admin` | `reviewer` only on entries from before [ADR 0009](decisions/0009-single-admin-role.md); new staff entries are `admin` |
| `note` | text? | The administrator's note, or the applicant's reply when resubmitting |
| `created_at` | timestamptz | |

### `businesses` (Phase 3 ✅)

Created only by `review_business_application(…, 'approve')`, in the same transaction as the approval. Read: the owner and administrators directly; other students see an approved business's storefront through `get_storefront()`. The owner changes the storefront (description, pickup details, map pin, logo) through `update_storefront()`. No client writes.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `owner_id` | uuid | The applicant; one business per student |
| `application_id` | uuid | The approved application; unique |
| `name`, `description` | text | From the application; the owner may edit the description |
| `logo_path` | text? | `{business_id}/{file}` in `business-logos`, set by `update_storefront()` |
| `pickup_details` | text | From the application's `collection_details`; the owner may edit it. Copied into each ready-stock order |
| `pickup_lat`, `pickup_lng` | double precision? | Optional map pin of the pickup spot, set by `update_storefront()`; same rules as on `listings` ([pickup pins](#pickup-pins)) |
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

An order for a business product: ready stock (no campaign) or a pre-order (with a campaign). Written only by `place_order()` and `transition_order()`. Read (every column except `cost_sen`): the buyer, the business owner (also while the business is suspended) and admins; the apps use `my_orders()`, which adds names and, once confirmed, contact emails.

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
| `cancelled_by` | `buyer` \| `seller` \| `system`? | Set exactly when `cancelled`. A seller cancelling a pending order is a rejection; `system` means a transfer payment's proof didn't arrive in time ([ADR 0005](decisions/0005-transfer-payments.md)) |
| `cost_sen` | integer? | The seller's own cost for this order (0–100,000,000), for estimated profit. Written only by `set_order_cost()` (Phase 6); self-reported, never verified. Not selectable from the table by anyone: the seller gets it through `my_orders('selling')` and `business_dashboard` ([ADR 0007](decisions/0007-admin-business-performance.md)). A new column on this table needs its own select grant |
| `completed_at` | timestamptz? | Set exactly when `completed`; M5 date filters and totals |
| `created_at`, `updated_at` | timestamptz | |

**Quantity is held from the moment of ordering.** `place_order()` locks the listing (ready stock) or the campaign (pre-order), checks what is left and takes it in one transaction, so two buyers can never get more than exists: the second waits for the lock, then gets `ITEM_UNAVAILABLE` or `CAPACITY_FULL`. A ready-stock order takes units out of `listings.stock` (the listing becomes `sold` at 0); a pre-order adds to `campaigns.allocated_qty` and doesn't touch the listing's stock. Cancelling returns them; progressing and completing keep them (capacity is a fulfilment limit, so a completed pre-order still counts). No money moves through the app: buyers pay cash on pickup, or by transfer to the seller's own account with proof the seller checks (`deal_payments`).

### `product_requests` (Phase 5 ✅)

A student asking for a product nobody sells yet (M4). Written only by `create_product_request()` and `close_product_request()`. Verified students read active requests and their own; admins read all. The apps use `list_product_requests()`, which adds interest counts without naming anyone.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `creator_id` | uuid | The caller; can't change |
| `name` | text | 3–80 characters, e.g. "chocolate brownie" |
| `normalized_name` | text | Server: the name's discovery terms joined by spaces (see "Discovery terms" below) |
| `category` | text | One of `app_config.categories` |
| `preferred_price_sen` | integer? | 0–10,000,000: what the student would like to pay |
| `campus_area` | text | 2–80 characters, e.g. "Desasiswa Tekun" |
| `notes` | text? | Up to 300 characters |
| `cluster_key` | text | Server: `{category}\|{head term}`, e.g. `Food & Beverage\|brownie` |
| `status` | `active` \| `closed` | The creator closes it when no longer needed; closed requests leave M4 |
| `created_at`, `updated_at` | timestamptz | |

A student has at most one active request per cluster (`ALREADY_EXISTS`) and may make 10 requests a day.

### `request_interests` (Phase 5 ✅)

`request_id`, `user_id`, `created_at`. The primary key `(request_id, user_id)` allows one interest per student per request. Written only by `toggle_request_interest()`; a student reads their own. The creator can't add interest to their own request (they are already counted).

### `opportunities` (Phase 5 ✅)

The M4 result per cluster, written only by `recompute_opportunities()` (from triggers). Verified students and staff read it. A cluster with no active request has no row. "Possible opportunity": demand signals are not confirmed purchases.

| Column | Type | Notes |
|---|---|---|
| `cluster_key` | text | Primary key |
| `category`, `head_term` | text | The cluster's category and main word |
| `keywords` | text[] | Every discovery term in its requests, sorted |
| `request_ids` | uuid[] | Its active requests, oldest first |
| `unique_interest_count` | integer | **D**: distinct students among the requests' creators and interested students (each counted once) |
| `active_supply_count` | integer | **S**: matching listings (same category, head term among the title's discovery terms) that are `available`, not hidden, from an active seller and, for business products, an approved business |
| `distinct_seller_count` | integer | Distinct owners of those listings |
| `median_listed_price_sen`, `median_preferred_price_sen` | integer? | Medians (rounded to the sen) of the matching listings' prices and the requests' preferred prices |
| `price_gap` | boolean | Both medians exist and the listed one is higher |
| `score` | integer | `max(0, 5 × min(D, 20) − 8 × min(S, 10) + (10 if price_gap else 0))` |
| `reasons` | text[] | The explanation, built from the same numbers |
| `insufficient_data` | boolean | `D < 2` |
| `algo_version` | text | `m4-v1` |
| `params` | jsonb | The weights and caps used, so results are reproducible |
| `last_interest_at` | timestamptz | Newest request or interest; breaks score ties |
| `calculated_at` | timestamptz | |

Ranking: `score` descending, then `last_interest_at` descending, then `cluster_key`.

**Discovery terms** (`discovery_terms(text)`): the text is lowercased and punctuation removed (`normalize_text`); words shorter than 2 letters and stop words (English and campus Malay, e.g. "the", "for", "cheap", "nak", "murah") are dropped; each word is mapped through `discovery_synonyms` (curated: plural forms like "brownies" → "brownie", and synonyms like "calc" → "calculator"), singularised by simple rules ("batteries" → "battery", "boxes" → "box", "chargers" → "charger"), then mapped through the synonyms again. The **head term** is the last term: "chocolate brownie" → `brownie`.

### `discovery_synonyms` (Phase 5 ✅)

The curated synonym and plural list: `term` (primary key) → `canonical`. Seeded by the migration; changed only in the Supabase dashboard. No client access.

### Pickup pins

Added after the handoff (`20261118000000_pickup_pins`). A seller may pin where buyers collect a listing (`listings.pickup_lat`, `pickup_lng`), and a business where buyers collect its orders (`businesses.pickup_lat`, `pickup_lng`). The pin is optional and sits beside the required pickup text. Check constraints keep both coordinates or neither, inside Malaysia's bounding box (every USM campus is in it); the functions give the same rule a readable reason through the internal helper `pickup_pin_problem(lat, lng)`. A pin is shown to everyone who can see the listing or storefront, so the app asks for a public spot, never a room. The app's maps use OpenStreetMap tiles (no API key) and credit OpenStreetMap as its licence requires.

### `reports` (Phase 2 ✅)

Written only by `report_listing()` and `report_conversation()` (students) and the admin functions. Reporters read their own; admins read all. Never deleted.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `reporter_id` | uuid | The student who reported |
| `listing_id` | uuid? | The reported listing (listing reports) |
| `conversation_id` | uuid? | The reported chat (chat reports, [ADR 0004](decisions/0004-deal-chat.md)) |
| `reported_user_id` | uuid? | The listing's owner at the time, or the other chat participant |
| `reason` | `prohibited_item` \| `scam` \| `offensive` \| `misleading` \| `other` | `other` needs details |
| `details` | text | Up to 500 characters |
| `status` | `open` \| `reviewed` \| `actioned` | `reviewed`: dismissed. `actioned`: the listing was hidden or the account suspended |
| `action` | `dismissed` \| `listing_hidden` \| `account_suspended`? | Set exactly when the report is closed |
| `reviewed_by`, `reviewed_at`, `review_note` | | The admin's decision |
| `created_at`, `updated_at` | timestamptz | |

One open report per student per listing, and per chat. Students may send 10 reports a day. Chat reports use `scam`, `offensive` or `other`.

### `conversations` (chat, [ADR 0004](decisions/0004-deal-chat.md), [ADR 0006](decisions/0006-buy-now.md))

An **item chat** (no `order_id`): one per personal listing and student, opened before buying and kept for the handover. An **order chat**: one per confirmed business order. Written only by the chat functions; the two participants read it.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `order_id` | uuid? unique | Null for an item chat, which is unique per `listing_id` and `buyer_id` |
| `listing_id` | uuid | The item or product, for the chat's title |
| `buyer_id`, `seller_id` | uuid | For an item chat, `buyer_id` is the student asking. For an order, the seller is the business owner. Never equal |
| `buyer_last_read_id`, `seller_last_read_id` | bigint | The newest message each has seen (0 = none); unread = later messages from the other person |
| `last_message_at` | timestamptz? | |
| `closed_at`, `closed_by` | timestamptz?, uuid? | Set when a participant closes the chat (the block). Never reopened |
| `created_at`, `updated_at` | timestamptz | |

A chat **can send** while it isn't closed, neither participant is suspended and: for an item chat, the item is `available` and not hidden, or the student bought it (any purchase that wasn't cancelled, or a cancelled one they had sent money for); for an order chat, the order is `confirmed`, `preparing` or `ready_for_pickup` at an approved business. Otherwise it is read-only; its history stays readable. A seller doesn't list an item chat until it has a message.

### `messages` (chat)

Written only by `send_message()`; read by the chat's two participants (also through Supabase Realtime, which applies the same policy). Never edited or deleted, except with the chat or an account.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | Increases with every message; orders a chat |
| `conversation_id` | uuid | |
| `sender_id` | uuid | |
| `body` | text | 1–1,000 characters, trimmed |
| `created_at` | timestamptz | |

Students may send 20 messages a minute.

### `payment_details` (transfer payments, [ADR 0005](decisions/0005-transfer-payments.md))

Where buyers pay a seller by transfer. One row per student and, optionally, one per approved business (used for its orders instead). The app asks for a student's on the listing's payment step, and for a business's in My store ([ADR 0008](decisions/0008-listing-payment-and-delete.md)). Written only by `set_payment_details()`; only its owner reads the row. A buyer gets the details only through `get_payment()`, while their payment is open.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `profile_id` | uuid? unique | Exactly one of `profile_id` and `business_id` |
| `business_id` | uuid? unique | |
| `bank_name` | text? | 2–60 characters |
| `account_name` | text? | The account holder, 2–80 characters |
| `account_number` | text? | 6–20 digits (spaces and dashes are removed). The three bank fields are all set or all empty |
| `qr_path` | text? | `{owner_id}/{file}` in `payment-qr`; must be the owner's own upload |
| `created_at`, `updated_at` | timestamptz | |

At least an account number or a QR code. Saving neither removes the row.

### `deal_payments` (transfer payments)

The payment of one transfer order or purchase (cash deals have none). Written only by the ordering, buying and payment functions; the buyer and the seller read their own, admins read all.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `order_id` | uuid? unique | Exactly one of `order_id` and `purchase_id` |
| `purchase_id` | uuid? unique | |
| `buyer_id`, `seller_id` | uuid | For an order, the seller is the business owner |
| `business_id` | uuid? | Set for orders, so the business's own details are used |
| `amount_sen` | bigint | The order's or purchase's `total_sen` |
| `status` | `awaiting_proof` \| `submitted` \| `accepted` \| `rejected` \| `expired` \| `cancelled` | `awaiting_proof` → `submitted` (buyer, before `due_at`) → `accepted` / `rejected` (seller). `awaiting_proof` → `expired` after `due_at`. Either becomes `cancelled` when the deal is cancelled. A `submitted` payment never expires |
| `due_at` | timestamptz | 30 minutes after ordering or buying |
| `proof_path` | text? | `{buyer_id}/{payment_id}/{file}` in `payment-proofs`; set from `submitted` on |
| `submitted_at`, `decided_at` | timestamptz? | `decided_at` exactly when `accepted` or `rejected` |
| `reject_reason` | text? | 1–200 characters, exactly when `rejected` |
| `created_at`, `updated_at` | timestamptz | |

**The units stay held while a payment is open.** No proof by `due_at`: the order or purchase is cancelled (`cancelled_by = 'system'`) and the units go back on sale. Expiry is lazy: changing a listing's or campaign's stock expires its overdue payments first, and `search_listings`, `get_listing`, `get_storefront`, `my_orders`, `my_purchases` and `get_payment` sweep every overdue payment first, skipping rows another transaction holds. Accepting confirms the order or leaves the purchase awaiting handover; rejecting cancels it. The app records what the seller decided; it never checks a payment itself.

### `notifications` (Phase 2 ✅)

In-app notices written by database functions. The recipient reads their own and may set `read`; nothing else is writable.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | |
| `recipient_id` | uuid | |
| `type` | text | `order_placed`, `order_confirmed`, `order_preparing`, `order_ready_for_pickup`, `order_completed`, `order_cancelled`, `purchase_created`, `purchase_completed`, `purchase_cancelled`, `purchase_payment_expired`, `listing_hidden`, `listing_restored`, `application_under_review`, `application_info_requested`, `application_approved`, `application_rejected`, `business_suspended`, `business_reinstated`, `order_payment_expired`, `payment_submitted`, `payment_accepted`, `payment_rejected`. Notices from before ADR 0006 keep their `reservation_*` types |
| `target` | text? | What it's about, e.g. `purchase:{id}`, `listing:{id}`, `application:{id}`, `business:{id}` or `order:{id}` |
| `title`, `body` | text | |
| `read` | boolean | |
| `created_at` | timestamptz | |

## File storage (Supabase Storage buckets)

| Bucket | Contents | Access |
|---|---|---|
| `listing-photos` (Phase 2) | Product photos: JPEG, PNG or WebP, up to 5 MB, under `{owner_id}/{listing_id}/` | Private bucket. A verified student uploads only into a folder of a listing they own (`can_upload_listing_photo`) and deletes only their own files; verified students and admins read, with their sign-in token |
| `application-documents` (Phase 3) | Business application documents: PDF, JPEG or PNG, up to 5 MB, under `{applicant_id}/{application_id}/` | Private. The applicant uploads and deletes only while their application is `draft` or `info_requested`, up to `app_config.max_application_documents` files (`can_upload_application_document`); files are never overwritten. The applicant, and administrators once it is submitted, read through short-lived signed URLs (`can_read_application_document`) |
| `business-logos` (Phase 4) | Business logos: JPEG, PNG or WebP, up to 2 MB, under `{business_id}/` | Private bucket. The owner of an approved business uploads into its folder (`can_upload_business_logo`) and deletes its own files; verified students and staff read with their sign-in token |
| `payment-qr` (ADR 0005) | Sellers' payment QR codes: JPEG, PNG or WebP, up to 2 MB, under `{owner_id}/` | Private. A verified student uploads into and deletes from their own folder only. Read by the owner, and by a buyer whose payment to that seller is open (`can_read_payment_qr`) |
| `payment-proofs` (ADR 0005) | Buyers' payment screenshots: JPEG, PNG or WebP, up to 5 MB, under `{buyer_id}/{payment_id}/` | Private. The buyer uploads up to 3 files while the payment is `awaiting_proof` and before its deadline (`can_upload_payment_proof`), and deletes them until sending. Read by the buyer, the seller and admins (`can_read_payment_proof`) |
