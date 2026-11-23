# 0007: Let administrators see student business performance

- **Status:** Accepted by the project owner (23 Nov 2026); to be confirmed with the FYP supervisor
- **Date:** 23 Nov 2026
- **Changes:** the handoff's M5, which shows performance only to each business's owner on mobile

## Context

The project owner wants administrators to follow how student entrepreneurs are doing. M5's `business_dashboard` deliberately takes no business id, so nobody could see another business's figures.

Sellers type in their costs for their own use, and the figures are self-reported. Showing them to staff is a privacy (PDPA) question.

While designing this, a leak was found: `orders.cost_sen` was granted with the rest of the row, so a buyer or an admin could read a seller's cost straight from the table.

## Decision

| Rule | Detail |
|---|---|
| Who | Admins only. Reviewers decide applications and don't need sales figures |
| What | Per business: orders by status, completed orders, estimated revenue, best sellers, stock and pre-order places. Across businesses: the totals |
| Never | A seller's cost or profit, or their personal (Buy now) sales |
| Trail | Every list or business view is audited (`performance.list_viewed`, `performance.viewed`), without the figures |
| Transparency | The seller's dashboard says what administrators can see. Both admin pages say "Estimated (self-reported)" and that it isn't an official assessment |
| One source | `business_figures()` computes both the owner's and the admin's figures, so they can't drift apart |
| The leak | `cost_sen` is no longer selectable. Owners get it through `my_orders('selling')` and `business_dashboard` |

## Consequences

- Migration `20261123000100_admin_business_performance`, with pgTAP file 25.
- The web dashboard gains Business Performance (a list and a page per business).
- A column added to `orders` later must be granted explicitly, and `select *` on `orders` no longer works for clients (none used it).
- The FYP report needs a use case, a functional requirement and a privacy note for this.
