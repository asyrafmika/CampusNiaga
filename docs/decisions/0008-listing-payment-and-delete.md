# 0008: Enter payment details with the listing, and delete listings instead of closing them

- **Status:** Accepted by the project owner (23 Nov 2026)
- **Date:** 23 Nov 2026
- **Changes:** where [ADR 0005](0005-transfer-payments.md) put a student's payment details (Profile), and the `closed` listing status from Phase 2

## Context

Students set up their bank account or QR code in Profile, separately from selling, so many sellers would never find it and their buyers could only pay cash. The project owner wants it where the seller already is: right after describing the item. Payment details in Profile are for student entrepreneurs only.

A seller could close a listing and re-open it later. The project owner wants sellers to delete listings instead.

## Decision

**Payment details**

| Rule | Detail |
|---|---|
| Where | A second step of the listing form, "How buyers pay you", after the item details. Publishing happens on that step. Editing a listing goes through it too, and publishing a draft from its page opens it |
| Storage | Unchanged: one set per student (`payment_details`), filled in from last time and used for all their items. Saving only happens when something changed |
| Optional | Leaving everything empty means cash only |
| Businesses | A business product skips the step: the business's own details are in My store, as before. Profile no longer has Payment details |

**Delete instead of close**

| Rule | Detail |
|---|---|
| Who | The owner, from any status but `deleted` |
| Effect | Status `deleted`: out of the marketplace, the storefront and the owner's list, and it can't be edited, bought, reported or chatted about anew. A business product's draft and open pre-orders close with it |
| Kept | The row stays, because purchases, orders, chats and reports point at it. The owner, admins and a student who bought it can still open it |
| Final | Nothing brings it back: cancelling or relisting a purchase leaves it deleted |
| Closing | No longer possible. A listing closed before this change can be re-opened or deleted |
| Cancelling a sale | The seller relists the item or deletes the listing (`cancel_purchase(..., relist => false)`) |

## Consequences

- Migration `20261123000200_delete_listings` and pgTAP file 26. The photo rule on `listings` now allows `deleted` without a photo, so an empty draft can be deleted.
- Deleted listings keep their photos in storage, as the purchases that show them still need them.
- The FYP report's "edit or delete" wording for listings is right again, and the requirement for payment details belongs with listing management (M1) rather than the profile.
