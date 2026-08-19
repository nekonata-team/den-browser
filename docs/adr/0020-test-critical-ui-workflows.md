---
status: accepted
---

# Test critical UI workflows instead of input permutations

XCUITests cover independent, deterministic, user-visible workflows that cross native UI boundaries unit tests cannot observe and whose failure would block meaningful use of Den Browser. Keep unrelated behavior out of one workflow; cover exhaustive shortcut mappings, state transitions, branches, and edge cases with focused unit tests.
