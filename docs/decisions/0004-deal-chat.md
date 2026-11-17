# 0004: Add a chat limited to agreed deals

- **Status:** Accepted by the project owner (17 Nov 2026); to be confirmed with the FYP supervisor
- **Date:** 17 Nov 2026
- **Changes:** the handoff's and CLAUDE.md's "never build: chat or messaging" rule, for this one limited case

## Context

The handoff (v1.0, 24 Oct 2026) lists chat and messaging as out of scope. Buyers and sellers arrange payment and pickup themselves, so after a reservation is accepted the app only reveals the other person's email.

Testing on a phone showed that this is the weakest step of the journey. Students have to leave the app to agree a time and place, which is the WhatsApp habit CampusNiaga is meant to replace. The project owner asked for live chat between buyer and seller.

General messaging would bring spam, harassment and moderation load that a prototype can't handle, so the chat has to be as narrow as possible.

## Decision

A **deal chat**: one conversation per reservation or business order, between its buyer and its seller only.

| Rule | Detail |
|---|---|
| When it opens | A reservation is `accepted`, or an order is `confirmed`, `preparing` or `ready_for_pickup`. Nobody can message a stranger, and there's no chat before the seller has agreed |
| When it closes | It becomes read-only when the deal ends (collected, completed, declined, cancelled or expired) or when either person closes it (the "block"). History stays readable for both |
| Who sees it | The two participants, through Row Level Security. Admins see a conversation only when one of the two reports it, through an audited function |
| Writes | Only through database functions (`open_conversation`, `send_message`, `mark_conversation_read`, `close_conversation`, `report_conversation`): caller, state and text checked, rate-limited (20 messages a minute) |
| Live updates | Supabase Realtime on `messages`, which applies the same Row Level Security |
| Moderation | Reports go into the existing `reports` table with a `conversation_id`. Admins dismiss them or suspend the account, as for listing reports |

Text only: no images, files, payments or links that pay anyone. Payment and delivery stay out of scope.

## Consequences

- One new migration with two tables (`conversations`, `messages`) and a `conversation_id` on `reports`, with pgTAP tests for every policy and function.
- The mobile app gains a Messages list and a chat screen, opened from Bookings and My orders. The admin moderation page labels chat reports and can open the reported conversation.
- Message bodies are personal data. They're kept as long as the deal, and deleted with the accounts involved (cascade).
- The project scope is larger than the handoff. The FYP report should say so and point to this record.
