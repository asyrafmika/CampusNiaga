# 0005: Let buyers pay by bank transfer or QR, with proof the seller checks

- **Status:** Accepted by the project owner (18 Nov 2026); to be confirmed with the FYP supervisor
- **Date:** 18 Nov 2026
- **Changes:** the handoff's and CLAUDE.md's "never build: in-app payments … or verification" rule, for this one limited case

## Context

The handoff (v1.0, 24 Oct 2026) keeps payment out of scope: buyers and sellers settle it themselves, usually in cash at pickup. SRD section 3.3 says the same, and adds that the system can't confirm whether a payment was made.

Students increasingly pay each other by DuitNow QR or bank transfer. The project owner asked for a pay-by-transfer step:
- the seller saves a QR code or bank account;
- the buyer sees it after buying and uploads a screenshot as proof;
- the seller checks and accepts or rejects it.

The item must be held for the buyer meanwhile, and released if the payment is rejected.

A payment gateway, wallet or any handling of money would bring licensing, fraud and refund obligations a student prototype can't carry. The step therefore has to stay a record of what the seller decided, never a payment system.

## Decision

**Manual transfer with proof**, next to cash on pickup. No money ever passes through CampusNiaga.

| Rule | Detail |
|---|---|
| Payment details | One set per student (bank, account holder, account number and/or a QR image), and optionally one for their approved business, used for its orders. Only the owner reads the row. A buyer sees the details only through `get_payment`, while their payment is open |
| Choosing | The buyer chooses cash or transfer when reserving or ordering. Transfer is offered only when the seller has details (`seller_accepts_transfer`). Cash works as before |
| Holding the item | Units are taken at once, as before, under the same row lock. A transfer deal gets a `deal_payments` row with **30 minutes** to send proof |
| No proof in time | The order is cancelled (`cancelled_by = 'system'`), or the reservation expires, and the units go back on sale. Expiry is lazy: changing the stock expires that listing's or campaign's overdue payments, and read functions sweep all overdue payments first, skipping rows another transaction holds |
| Proof sent | A screenshot in the private `payment-proofs` bucket. The hold then waits for the seller (a reservation for up to 7 days). A buyer who has sent proof can't cancel on their own; the seller cancels and refunds them |
| The seller's decision | `review_payment`: accepting confirms the order or accepts the reservation; rejecting needs a reason and cancels or declines it, returning the units. Decisions are audited |
| Wording | The app says "the seller confirmed your payment", never "paid". It reminds sellers to check their own bank and buyers to pay only the details shown |
| Who sees proof | The buyer, the seller, and admins (for disputes) |

Still out of scope: payment gateways, wallets, refunds through the app, automatic checking of receipts, and delivery.

## Consequences

- One new migration (`20261119000000_transfer_payments`):
  - two tables, `payment_details` and `deal_payments`;
  - two private buckets, `payment-qr` and `payment-proofs`;
  - `request_reservation` and `place_order` take a `payment_method`;
  - `resolve_reservation` and `transition_order` gain payment guards;
  - the read functions (search, listing, storefront, My Orders, Bookings) become volatile so they can sweep expired holds.
- pgTAP file 24 covers every policy, bucket and function, the 30-minute hold and both kinds of expiry.
- The mobile app gains Payment details (Profile, and My store for the business), a cash/transfer choice when ordering or reserving, and a payment page for both sides. The order and booking cards show the payment and the next step.
- Bank details and payment screenshots are personal data (PDPA). They're readable only as described above and deleted with the accounts involved (cascade).
- The project scope is larger than the handoff, and SRD section 3.3 ("the system cannot confirm whether a payment has been made") stays true: the seller confirms, not the system. The FYP report should describe this feature and point to this record.
