# 0006: Replace reservations with Buy now for personal items

- **Status:** Accepted by the project owner (23 Nov 2026); to be confirmed with the FYP supervisor. The 24-hour relist and the limit of 3 cash purchases are initial values the project owner hasn't yet confirmed
- **Date:** 23 Nov 2026
- **Changes:** the handoff's M1 reservations; widens [ADR 0004](0004-deal-chat.md) (chat before a deal) for personal items; replaces the reservation parts of [ADR 0005](0005-transfer-payments.md) and the reservation expiry of [ADR 0002](0002-server-mediated-writes-and-query-strategy.md)

## Context

A reservation took an item off sale for up to 48 hours while the seller answered and 7 days afterwards, so one buyer who didn't turn up could stop a seller from selling. A buyer also couldn't ask about an item's condition before reserving it, because chat opened only after acceptance. Overdue cash reservations were released only when one of the two sides came back to them.

The project owner decided that students should ask the seller first, then buy directly: the item is sold when the buyer confirms.

## Decision

**Chat doesn't hold an item. Confirm purchase does: first come, first served.**

| Rule | Detail |
|---|---|
| Asking | Any student can chat about an available personal item. One chat per item and student, at most 20 new ones a day. The seller sees a chat once it has a message |
| Buying | Buy now, choose cash or transfer, then **Confirm purchase**. The units leave stock at once under the listing's row lock, and the listing is `sold` at 0. The seller doesn't accept |
| Purchase states | `awaiting_payment` (transfer) → `awaiting_handover` → `completed`; either of the first two → `cancelled` |
| Cash | The buyer may cancel. The seller may relist 24 hours after the purchase if it wasn't collected. Never released automatically, as the item may have changed hands |
| Transfer | 30 minutes to send a receipt, otherwise released automatically. Rejected: released. Receipt sent: never released automatically, and the buyer can't cancel alone |
| Seller can't sell | Cancels with a reason, and chooses to relist or close. Refunds happen outside the app |
| Handover | The seller completes the sale |
| Limits | At most 3 unfinished cash purchases and 10 purchases an hour per student; one unfinished purchase per student and listing |
| Contact | No email is shared. The item chat stays open to the student who bought it |
| Business products | Unchanged: ordered, with chat once the order is confirmed |

Chat remains text only, between two people, about one item or order. There is still no general messaging between students.

## Consequences

- Migration `20261123000000_buy_now` replaces `reservations` with `purchases`, removes the `reserved` listing status, and moves payments and chats across. Purchases keep their reservation's id. Waiting cash requests and accepted reservations become purchases awaiting handover; overdue ones are released by the old rules, except where a receipt was sent.
- The original rows are kept in `legacy.reservations`, which the API doesn't expose and which can be dropped once no longer needed.
- App versions before this change stop working for reservations, chat and payments once the migration is applied, so the migration and the new app are released together.
- A cash purchase costs the buyer nothing, so it can delay a sale for a day. The limit, the seller's cancel and Relist contain this.
- A receipt the seller never checks keeps the item sold until the seller acts; the buyer can chat with or report the seller.
- Students can now be messaged by strangers about their items. The daily limit, close (block), report and the audited admin view are the safeguards.
