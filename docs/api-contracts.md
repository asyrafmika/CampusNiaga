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
