---
status: accepted
---

# Use CLI Exit Codes for Operation Completion

Den CLI uses `0` for successful completion, `1` for execution failures, and `64` for invalid CLI usage detected before sending a request, following ArgumentParser's `EX_USAGE` convention rather than introducing codes for individual failure causes.
A successful lookup or state query returns `0` even when its result is false or empty, including an absent Board in `board exists`, so exit codes consistently describe operation completion rather than predicate truth.
JSON retains result values and error diagnostics independently of exit codes, supporting both `jq` consumers and agent harnesses that do not inspect process status; the existing JSON fields and output paths remain unchanged.
