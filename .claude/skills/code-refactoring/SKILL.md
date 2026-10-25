---
name: code-refactoring
description: Restructure existing CampusNiaga code without changing its behavior, such as extracting widgets, components, services or domain functions, moving code into the correct feature or layer, removing duplication, renaming internal identifiers, simplifying state machines, or cleaning up after a phase. Use when the user asks to refactor, clean up, reorganize or simplify code, or when code violates the layering in enterprise-architecture. Not for adding features or fixing bugs; those change behavior.
---

# Code refactoring

A refactor changes structure and keeps behavior identical. If behavior must change, it's a feature or a bug fix: do that separately, before or after, never mixed into the same change.

## Before you start

1. **Read the code and its callers.** Find every reference (Grep for the symbol, collection name or callable name across `mobile/`, `admin/`, `functions/`, `firebase/`, `seed/`, `docs/`).
2. **Check the user's uncommitted changes.** If the project is under git, run `git status` / `git diff`; never move, rename or reformat a file with unsaved user edits without asking.
3. **Make sure tests protect the behavior.** If the code to refactor has no tests, write characterization tests first that pin the current behavior (including odd behavior, which you report rather than fix).
4. **State the goal in one sentence** (e.g. "move listing price formatting from the widget into `core/utils/money.dart`").

## What counts as a public contract (don't change it in a refactor)

- Firestore collection names, field names, status values, document ID formats (`{requestId}_{uid}`, `clusterKey`).
- Callable names, input and output shapes, `details.reason` values.
- Storage paths, custom claim names, route paths used by deep links.
- `algoVersion` semantics in M4 outputs.

Changing any of these is a migration, not a refactor. Stop and propose it to the user with the affected data, clients and tests listed.

## Allowed refactors and their target

| Smell | Refactor to |
|---|---|
| Firestore/Functions call in a widget or React component | Move it into the feature's repository (Flutter) or service (React) |
| Business rule in UI (status branching, price math) | Domain function with unit tests |
| Long `build` method or component (more than about 80 lines) | Extract widgets/components inside the same feature |
| The same widget/component in two or more features | Move it to `core/widgets` or `shared/ui` |
| `if/else` chains over statuses | Transition table + `assertTransition` / `switch` over a sealed type or enum |
| Duplicate zod schemas or types | Single definition in `functions/src/domain` or `shared/types/domain.ts` |
| Callable handler with Firestore logic | Split into handler (guard + parse) and service |
| Speculative interface with one implementation | Inline it (remove the abstraction) |

Don't add new layers, generic base classes, dependency-injection frameworks or new packages as part of a refactor.

## Workflow

1. Make one mechanical step at a time (move, rename, extract). Each step compiles and keeps tests green.
2. After each step, run the narrow check for the touched package:
   - Mobile: `cd mobile && flutter analyze && flutter test`
   - Admin: `npm --prefix admin run typecheck && npm --prefix admin run test`
   - Functions: `npm --prefix functions run build && npm --prefix functions run test`
   - Rules: the emulator test command in CLAUDE.md
3. Don't reformat untouched code. Keep diffs reviewable: moves in one step, edits in the next.
4. Update imports, docs and skill references that name moved paths.
5. Finish with the full checks for every touched package.

## Reporting

Summarize: goal, files moved or created, why behavior is unchanged (tests that cover it), any behavior oddities found but **not** changed, and any follow-up that would need a real behavior change.

## Verification checklist

- [ ] No public contract changed (or the change was approved and handled as a migration).
- [ ] Tests existed or were added before the change, and all pass after it, with no test weakened.
- [ ] No new dependencies, abstractions or features introduced.
- [ ] User changes preserved; unrelated code untouched.
- [ ] Analyze, lint, typecheck and tests are clean for each touched package.
