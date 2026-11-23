# 0009: One staff role, the HDC administrator

- **Status:** Accepted by the project owner (23 Nov 2026)
- **Date:** 23 Nov 2026
- **Changes:** the two staff roles (reviewer, admin) from Phase 1 and the M2 reviewer workflow from Phase 3. Non-negotiable 2 in `CLAUDE.md` still holds: the role is read live from `staff_roles`

## Context

CampusNiaga had two staff roles. A **reviewer** decided business applications. An **admin** could do that too, and also moderated reports, managed users and roles, read the audit log and, since [ADR 0007](0007-admin-business-performance.md), saw student business performance.

At USM, one office handles all of this: the HDC administrator. The project owner wants one staff role only, so the person who reviews applications is the same person who runs the platform.

## Decision

| Rule | Detail |
|---|---|
| Role | `staff_roles.role` can only be `admin`, shown as "HDC Administrator". `is_reviewer()` is gone; `is_admin()` is the staff check, and `is_staff()` now means the same thing |
| Reviewing | `review_business_application` and `application_status_summary` are for administrators. An administrator still can't decide their own application, so a second administrator decides it |
| Existing reviewers | The migration makes each existing reviewer an administrator (audit `role.granted`, with no actor and a reason) and then deletes the reviewer rows. Nobody loses access to the review queue |
| Granting | `set_staff_role` accepts only `admin`. The dashboard has one switch per account |
| History | `application_status_history.actor_role` keeps `reviewer` on entries written before this change. New entries say `admin`. The apps label old entries "Reviewer" and new ones "HDC administrator" |
| Wording | Screens say "HDC administrator" or "administrator". The disclaimer stays: approval is a **simulated** reviewer workflow, not an official USM or HDC decision |
| Column names | `business_applications.reviewer_id` is renamed `admin_id` (migration `20261123000400_rename_reviewer_id`); `remarks` keeps its name and holds the administrator's note |

Migrations: `20261123000300_single_admin_role`, then `20261123000400_rename_reviewer_id`.

## Consequences

- The dashboard has no reviewer-only view. Every page is behind one check, and a signed-in account without the administrator role is signed out with the "staff only" message.
- A reviewer who should not have seen moderation, user management, the audit log or business performance would now see them. Before this change, someone who only reviewed applications had no access to those pages. Grant the role only to people who should have all of it.
- Self-review is still refused, so the review workflow needs at least two administrators for an administrator's own application. Students' applications need only one.
- Tests: pgTAP 03 (only `admin` can be stored, `is_reviewer` is gone), 04 (`get_my_access` has no `is_reviewer`), 09-11 (only administrators review; history records `admin`), and the dashboard and app tests that used a reviewer.
