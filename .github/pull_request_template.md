<!--
  Four checkboxes, one per class of mistake this repository has actually shipped:
    * a schema change without a migration test (drift had no onUpgrade at all);
    * a user-visible string that never went through the ARB files;
    * a version bump that touched some of the seven sync points (AGENTS.md §2);
    * a behaviour change with no assertion that can tell it changed.
  Delete the ones that do not apply rather than ticking them blindly.
-->
## What changed

<!-- One paragraph. If it fixes a defect, say what the user saw. -->

## Gates (AGENTS.md §4)

- [ ] `flutter analyze --no-pub` → **0 issues**
- [ ] `flutter test --no-pub -j 1` → **all green** (state the before/after counts)
- [ ] For a defect fix: **red → green evidence** (paste the failing assertion from the *old*
      code, and say how you restored the file — a `git stash`, a one-line mutation, …).
      "It passes now" is not evidence that it ever failed.
- [ ] Touched routing / background / bottom-layout (`app_router.dart`, `app_background*`,
      `miuix_bottom_stack`, `floating_glass_nav_bar`, …) → red→green verified for the new
      assertions, per AGENTS.md §4.

## Checklist

- [ ] **Schema**: no table/column/index change — **or** `schemaVersion` was bumped, an
      `onUpgrade` branch was added, and `test/database_migration_test.dart` covers a
      *real* old database being upgraded (with data preserved and fresh/upgraded parity
      asserted as an equality, not `containsAll`).
- [ ] **i18n**: no new hard-coded user-visible string — **or** every new string went into
      `lib/l10n/app_zh.arb` + `app_en.arb` and `flutter gen-l10n` was re-run (the generated
      files are committed).
- [ ] **Version**: the version number was not touched — **or** all seven points in
      AGENTS.md §2 were updated (`test/version_sync_test.dart` enforces this).
- [ ] **Assertions**: every behaviour change has an assertion that fails on the old code.
      No assertion was loosened to make this PR pass.
- [ ] **Windows**: nothing under `windows/` or in a platform branch changed — **or**
      `flutter build windows --debug --no-pub` was run and passed.
- [ ] **Scope**: no file outside the intended scope was modified (say so if one had to be).

## Notes for the reviewer / known unverified

<!--
  Anything you could not verify: real-device behaviour, a visual result, a platform
  path. Name it. A "known unverified" list that is honest is worth more than a green
  tick that hides the gap.
-->
