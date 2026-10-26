# API contracts

The Cloud Functions that the mobile app and admin dashboard call. Data shapes are defined in the [data dictionary](data-dictionary.md).

All functions are Firebase **callable** functions in region `asia-southeast1`. Any operation that grants privileges, changes another user's data, or could conflict with another user (stock, capacity, reservations) goes through one of these functions. Clients never write those fields directly.

## Errors

Every function reports failures as an `HttpsError`. The error's `details.reason` is one of the values below, and clients map each reason to a user-facing message.

| `details.reason` | Meaning |
|---|---|
| `NOT_VERIFIED_STUDENT` | Caller is signed in but is not a verified USM student |
| `FORBIDDEN` | Caller lacks the required role or doesn't own the resource |
| `INVALID_INPUT` | Input failed validation |
| `NOT_FOUND` | A referenced document doesn't exist |
| `INVALID_TRANSITION` | The requested status change isn't allowed from the current status |
| `ITEM_UNAVAILABLE` | Listing is no longer available or stock ran out |
| `CAPACITY_FULL` | Pre-order campaign capacity is reached |
| `ALREADY_EXISTS` | Duplicate, e.g. an existing active reservation or open application |
| `RATE_LIMITED` | Too many requests in a short time |

## Planned functions

Each function's full input, output and side effects are documented when it is implemented.

| Function | Phase | Caller | Purpose |
|---|---|---|---|
| `syncStudentStatus` | 1 | Any signed-in user | Grant the `student` claim if the email is verified and matches the USM domain or the test allowlist; create the user profile |
| `setStaffRole` | 1 | Admin | Grant or remove the `reviewer` / `admin` claim |
| `upsertListing` | 2 | Student (business mode: business owner) | Create or edit a listing; validates input, rate-limits, computes `normalizedTitle` and `searchTokens`, snapshots seller names |
| `setListingStatus` | 2 | Listing owner | Publish a draft, close a listing, or return it to available |
| `requestReservation` | 2 | Student | Reserve a personal listing |
| `resolveReservation` | 2 | Seller / buyer | Accept, decline, cancel or mark collected |
| `moderateListing` | 2 | Admin | Hide or restore a reported listing |
| `setAccountStatus` | 2 | Admin | Suspend or reactivate an account |
| `submitBusinessApplication` | 3 | Student (applicant) | Submit or resubmit an application |
| `reviewBusinessApplication` | 3 | Reviewer | Start review, request info, approve or reject |
| `setBusinessStatus` | 3 | Admin | Suspend or reinstate a business |
| `placeOrder` | 4 | Student | Order ready stock or join a pre-order campaign |
| `transitionOrder` | 4 | Business owner / buyer | Move an order through its statuses, or cancel it |
| `toggleRequestInterest` | 5 | Student | Add or remove interest in a product request |
| `recomputeOpportunities` | 5 | Trigger / schedule | Recalculate the M4 opportunity ranking |

---

<!-- Detailed contracts are appended below as each function is implemented. -->

## `syncStudentStatus`

Grants the `student` claim to a verified USM student and creates or updates their `users/{uid}` profile. The app calls it after sign-in and after the user verifies their email.

| | |
|---|---|
| **Caller** | Any signed-in user |
| **Input** | None. Anything sent is ignored; the email and verification status are read from Firebase Auth on the server |
| **Output** | `{ student: true, claimsChanged: boolean }`. When `claimsChanged` is `true`, the client must refresh its ID token (`getIdToken(true)`) to see the claim |
| **Eligibility** | Email verified, **and** the email's domain exactly matches one of `config/app.studentEmailDomains` (default `student.usm.my`), **or** the email is in `config/app.testAllowlist`. Matching is case-insensitive; subdomains and look-alike domains don't match. A missing or malformed `config/app` uses the default domain |
| **Errors** | `FORBIDDEN` (not signed in, or account suspended) · `NOT_VERIFIED_STUDENT` (email not verified, or not an eligible email) · `NOT_FOUND` (Auth user missing) |
| **Side effects** | Creates `users/{uid}` (`verified: true`, `accountStatus: 'active'`, `roleFlags`) or updates `verified`, `email` and `roleFlags.student`. Merges `student: true` into the custom claims, keeping other claims. Writes audit entry `student.verified` the first time only |
| **Idempotent** | Yes. Repeated calls change nothing and write no new audit entries |

## `setStaffRole`

Grants or removes the `reviewer` or `admin` role.

| | |
|---|---|
| **Caller** | Admin (`admin` claim) |
| **Input** | `{ uid: string (1–128 chars), role: 'reviewer' \| 'admin', enabled: boolean }` |
| **Output** | `{ uid, role, enabled, changed: boolean }`. `changed` is `false` when the user already had (or already lacked) the role |
| **Errors** | `FORBIDDEN` (not signed in, not an admin, or an admin removing their own admin role) · `INVALID_INPUT` · `NOT_FOUND` (no such user) |
| **Side effects** | When `changed`: merges the claim (other claims kept), updates `users/{uid}.roleFlags.<role>` (creating a minimal profile for staff who never used the app), and writes audit entry `role.granted` or `role.revoked` with `metadata.role`. Removing a role also revokes the user's refresh tokens, so they must sign in again |
