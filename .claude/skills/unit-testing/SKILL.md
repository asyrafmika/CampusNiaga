---
name: unit-testing
description: Write, organize, run or fix CampusNiaga tests, including Dart unit and widget tests in mobile/, Vitest and React Testing Library tests in admin/, Vitest domain tests, Security Rules tests and callable integration tests on the Firebase Emulator Suite in functions/, concurrency (race) tests, and the shared scenario fixture. Use when adding tests for new code, reproducing a bug with a failing test, proving a phase pass condition, or diagnosing flaky or failing tests.
---

# Testing: CampusNiaga

This skill covers **how** to test. CLAUDE.md lists **what** must be tested (testing requirements). Never weaken, skip or delete a test to make a build pass. Fix the code, or ask the user if the test itself is wrong.

## Test layers

| Layer | Location | Tooling | Needs emulator | What it proves |
|---|---|---|---|---|
| Domain unit | `functions/test/unit`, `mobile/test/**/domain`, `admin/src/**/*.test.ts` | Vitest / `flutter_test` | No | State machines, money, M4 normalization and scoring, validators |
| Rules | `functions/test/emulator/rules/*.test.ts` | `@firebase/rules-unit-testing` + Vitest | Firestore, Storage | Allowed actor can, other actors can't |
| Callable integration | `functions/test/emulator/callable/*.test.ts` | Vitest + Admin SDK + `firebase-functions-test` or HTTP callable against the Functions emulator | All | Guard, validation, transaction, audit, side effects |
| Flutter controller | `mobile/test/features/<feature>/...` | `flutter_test` + `mocktail`, `ProviderContainer` overrides | No | Controller state transitions and error mapping |
| Flutter widget | `mobile/test/features/<feature>/presentation/...` | `flutter_test` | No | Loading, empty, error and data rendering; intents call the controller |
| React component/hook | next to the source as `*.test.tsx` | Vitest + React Testing Library | No | Rendering states, role-filtered actions, mutations invoked |

Most tests should be domain and rules tests. Write UI tests for key states, not every pixel.

## Conventions

- **Names describe behavior:** `test('rejects reservation when listing is already reserved')` / `it('denies a student reading another applicant\'s application')`.
- **Arrange-Act-Assert**, one behavior per test, no logic (loops or ifs) in test bodies except table-driven cases.
- **Table-driven state machines:** iterate every `(from, to)` pair and assert allowed or rejected against the transition table, so no transition goes untested.
- **Deterministic:** inject `clock.now()`. Use fixed UIDs and IDs from the fixture. No real network, no `sleep`; await emulator writes.
- **Isolation:** clear Firestore and Auth emulator data in `beforeEach` (`clearFirestore`, Auth emulator REST `DELETE /emulator/v1/projects/{id}/accounts`). Use a unique `projectId` per test file so suites can run in parallel.
- **Money:** assert integer sen values exactly.
- **Error assertions** check `details.reason`, not message text.

## Rules test template

```ts
const student = env.authenticatedContext('stu1', { email_verified: true, student: true });
const other   = env.authenticatedContext('stu2', { email_verified: true, student: true });
await assertSucceeds(getDoc(doc(student.firestore(), 'businessApplications/app1')));
await assertFails(getDoc(doc(other.firestore(), 'businessApplications/app1')));
```

Each rule needs an allow case plus deny cases for: unauthenticated, unverified, wrong owner, wrong role, and a forbidden field change (`status`, `ownerUid`, `roleFlags`).

## Concurrency (race) tests

Required for reservations, stock and campaign capacity (handoff phases 2 and 4):

```ts
const results = await Promise.allSettled([placeOrder(buyerA, 2), placeOrder(buyerB, 2)]); // capacity 3
expect(results.filter(r => r.status === 'fulfilled')).toHaveLength(1);
expect(rejectedReason(results)).toBe('CAPACITY_FULL');
expect((await campaign()).allocatedQty).toBe(2);
```

## Flutter specifics

- Override repository providers: `ProviderScope(overrides: [listingRepositoryProvider.overrideWithValue(fakeRepo)])`.
- Use `mocktail` for repositories; build fakes for streams with `StreamController`.
- Widget tests pump `MaterialApp` with the app theme. Find widgets by `Key`s defined as constants for the important controls.
- No Firebase initialization in unit or widget tests. Code that needs Firebase belongs in the data layer, which is covered by emulator integration tests.

## React specifics

- Mock `services/*` modules with `vi.mock`, not the Firebase SDK internals.
- Wrap renders in a test `QueryClientProvider` (retries off) and a `MemoryRouter`.
- Query elements by role and label (`getByRole('button', { name: /approve/i })`), not by CSS class.

## Scenario fixture (`seed/src/scenario.ts`, used by the seed and its emulator tests)

Target: 2 students, 1 applicant, 1 approved business seller, 1 reviewer, 1 admin; 2 personal listings, 2 business products, 1 pre-order campaign (capacity 3); 3 similar requests ("brownie", "brownies", "chocolate brownie"); 1 competing listing. Each phase adds its part; Phase 1 has the students, reviewer, admin and a refused outsider. Export typed IDs so code references `users.reviewer.uid`, not string literals.

## Workflow

1. For a bug, write a failing test that reproduces it first.
2. For a feature, test the domain first, then rules, then the callable, then the client controller and UI.
3. Run the narrowest suite while iterating, then the full commands from CLAUDE.md before finishing.
4. Report the commands run and their pass/fail output. Never report success without running them.

## Verification checklist

- [ ] Every new transition, rule and callable has the tests CLAUDE.md requires.
- [ ] Deny cases exist for every rule touched.
- [ ] Race tests exist for stock, capacity and reservation changes.
- [ ] Tests are deterministic (injected clock, fixture IDs, cleared emulator state).
- [ ] No skipped, `.only`, or commented-out tests left behind.
