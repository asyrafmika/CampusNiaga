# Usability test kit

Everything needed to run CampusNiaga's usability test with real students and record the results: the plan, a script to read out, the tasks, an observation sheet, the System Usability Scale (SUS) questionnaire and a results template. The handoff (section 9, Phase 6) asks for usability testing; this kit makes it repeatable. Fill in section 8 once the sessions have been run.

## 1. What the test measures

| Measure | How | Target |
|---|---|---|
| Task success | Observer marks each task: completed unaided, completed with help, or failed | At least 80% of tasks completed unaided |
| Time on task | Stopwatch from "begin" to the success point | Under the task's time limit |
| Ease per task | Single Ease Question (SEQ) after each task: "Overall, this task was…" 1 (very difficult) to 7 (very easy) | Median 5 or more |
| Overall usability | SUS questionnaire at the end (section 6) | Mean score 68 or more (the commonly cited average) |
| Problems | Observer notes each problem and rates its severity (section 7) | No unresolved severity 3–4 problem |

## 2. Participants

- **Five to eight USM students.** Five participants typically reveal most usability problems; more improve confidence in the numbers.
- A mix: at least two who have never seen the app, at least two who already sell things on campus (WhatsApp or Telegram groups), and at least one interested in running a small business.
- **Web dashboard (optional):** one or two people acting as reviewers, for the reviewer tasks.
- Each student needs their own `@student.usm.my` account in the hosted project. For anyone without one, add their email to `app_config.test_allowlist` in the Supabase dashboard (and remove it afterwards).

## 3. Before the sessions

1. Install the app on an Android phone or the emulator (`cd mobile && flutter run`, or install a build from `flutter build apk`).
2. Seed the hosted project with realistic data, using two of your own test accounts:
   - 6–8 personal listings across categories, with photos, 2 of them under RM 30 in Stationery (one a calculator).
   - One approved business ("Ali Bakes") with 2 products, a logo and an open pre-order (capacity 10).
   - 3 product requests for similar items (for example "brownie", "brownies", "chocolate brownie") so Discover has an opportunity to show.
   - One business application from a test account in `info_requested` with a reviewer note, for task T6.
3. Print one observation sheet (section 5) and one SUS form (section 6) per participant.
4. Keep a stopwatch, and decide whether to record the screen (ask permission first).

## 4. Session script (about 30 minutes)

Read this to each participant:

> Thank you for helping. We're testing the app, not you: if something is hard, that's the app's fault and exactly what we want to find. Please think aloud as you go: say what you're looking for and what you expect to happen. I can't help with the tasks themselves, but you can stop at any time. CampusNiaga is a final-year project prototype: no real money changes hands, and business approval here is a simulated reviewer workflow, not an official USM decision. I'll note what happens and your answers, without your name. Is that all right?

Then, for each task: read it out, hand over the card, start the stopwatch at "begin", stop it at the success point (or after the time limit), and ask the SEQ. After the last task, give the SUS form, then ask the debrief questions:

1. What was the easiest thing to do? The hardest?
2. Was anything surprising or confusing?
3. Would you use this instead of WhatsApp/Telegram groups to buy or sell on campus? Why or why not?
4. On the Discover screen, what do you think "possible opportunity" means? Would you trust it?
5. If you ran a business, would the dashboard figures be useful? What's missing?

### Tasks (mobile app)

Give each task on its own card, in this order. A participant's own account plays the role in brackets.

| # | Task (read out) | Module | Success point | Time limit |
|---|---|---|---|---|
| T1 | "Sign in to CampusNiaga with the account we gave you." | Access | The Home screen shows | 2 min |
| T2 | "You need a calculator for under RM 30. Find one and reserve it, asking to collect it after 5pm." | M1 | The reservation shows under Bookings | 4 min |
| T3 | "Sell something of yours: list a desk lamp for RM 15 with a photo, and publish it." | M1 | The listing is published | 5 min |
| T4 | "Check whether anyone has asked to reserve your things, and what state your own reservation is in." | M1 | Participant states both correctly | 2 min |
| T5 | "You want to sell brownies as a small business. Start an application, save it as a draft, then come back and submit it." | M2 | The application shows "Waiting for a reviewer" | 6 min |
| T6 | "(Using the second account) A reviewer has asked for changes to this application. Find out what they want, make the change and send it back." | M2 | The application is resubmitted with the change | 4 min |
| T7 | "Find Ali Bakes' storefront and pre-order two boxes from its open pre-order." | M3 | The pre-order shows under My orders | 4 min |
| T8 | "You can't find a phone stand on campus. Ask for one, and show interest in someone else's request." | M4 | The request exists and one Interested is ticked | 4 min |
| T9 | "Look at the top possible opportunity. Explain in your own words why it ranks there." | M4 | Participant names at least two of its reasons | 3 min |
| T10 | "(Using the business owner's account) Confirm the newest order, then mark it ready, record a cost of RM 8, and tell me the estimated profit for this month." | M3, M5 | Participant reads the correct profit | 6 min |

### Tasks (web dashboard, optional)

| # | Task | Module | Success point | Time limit |
|---|---|---|---|---|
| W1 | "Sign in as a reviewer and find the oldest application waiting for review." | M2 | The application's detail page is open | 3 min |
| W2 | "Ask the applicant to add their prices, then approve the other application in the queue." | M2 | One is `info_requested`, the other `approved` | 4 min |

## 5. Observation sheet (one per participant)

Participant code: ______ Date: ______ Device: ______ Observer: ______

| Task | Outcome (✓ unaided / H with help / ✗ failed) | Time (m:ss) | SEQ (1–7) | Problems seen (and severity 0–4) |
|---|---|---|---|---|
| T1 | | | | |
| T2 | | | | |
| T3 | | | | |
| T4 | | | | |
| T5 | | | | |
| T6 | | | | |
| T7 | | | | |
| T8 | | | | |
| T9 | | | | |
| T10 | | | | |
| W1 | | | | |
| W2 | | | | |

Debrief notes:

## 6. System Usability Scale (SUS)

The participant rates each statement from 1 (strongly disagree) to 5 (strongly agree), without overthinking.

| # | Statement | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| 1 | I think that I would like to use this app frequently. | ☐ | ☐ | ☐ | ☐ | ☐ |
| 2 | I found the app unnecessarily complex. | ☐ | ☐ | ☐ | ☐ | ☐ |
| 3 | I thought the app was easy to use. | ☐ | ☐ | ☐ | ☐ | ☐ |
| 4 | I think that I would need the support of a technical person to be able to use this app. | ☐ | ☐ | ☐ | ☐ | ☐ |
| 5 | I found the various functions in this app were well integrated. | ☐ | ☐ | ☐ | ☐ | ☐ |
| 6 | I thought there was too much inconsistency in this app. | ☐ | ☐ | ☐ | ☐ | ☐ |
| 7 | I would imagine that most people would learn to use this app very quickly. | ☐ | ☐ | ☐ | ☐ | ☐ |
| 8 | I found the app very cumbersome to use. | ☐ | ☐ | ☐ | ☐ | ☐ |
| 9 | I felt very confident using the app. | ☐ | ☐ | ☐ | ☐ | ☐ |
| 10 | I needed to learn a lot of things before I could get going with this app. | ☐ | ☐ | ☐ | ☐ | ☐ |

**Scoring:** for odd items (1, 3, 5, 7, 9) take the rating minus 1; for even items (2, 4, 6, 8, 10) take 5 minus the rating. Add the ten results and multiply by 2.5, giving a score from 0 to 100. A score above 68 is above average; around 80 or more is good.

## 7. Problem severity

| Rating | Meaning |
|---|---|
| 0 | Not a usability problem |
| 1 | Cosmetic: fix if there is time |
| 2 | Minor: low priority |
| 3 | Major: important to fix |
| 4 | Catastrophe: must fix before release |

## 8. Results (fill in after the sessions)

**Sessions:** ___ participants, dates ______.

### Per task

| Task | Completed unaided | With help | Failed | Median time | Median SEQ |
|---|---|---|---|---|---|
| T1 | | | | | |
| T2 | | | | | |
| T3 | | | | | |
| T4 | | | | | |
| T5 | | | | | |
| T6 | | | | | |
| T7 | | | | | |
| T8 | | | | | |
| T9 | | | | | |
| T10 | | | | | |
| W1 | | | | | |
| W2 | | | | | |

### SUS

| Participant | SUS score |
|---|---|
| P1 | |
| P2 | |
| P3 | |
| P4 | |
| P5 | |
| **Mean** | |

### Problems found

| # | Problem | Task | Participants affected | Severity | Fix or decision |
|---|---|---|---|---|---|
| 1 | | | | | |

### Conclusion

Summarise whether the targets in section 1 were met, the most important problems, and what was changed as a result.
