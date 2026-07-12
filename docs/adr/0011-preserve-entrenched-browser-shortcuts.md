---
status: accepted
---

# Preserve entrenched browser shortcuts selectively

Den Browser preserves browser shortcuts whose muscle memory is strong enough to outweigh the distinction between browser concepts and Den concepts. `Command` + `T` opens the Open Board panel in every keyboard context, and `Command` + `R` reloads the Current Sheet outside Den Mode. This supersedes ADR 0003's blanket avoidance of `Command`-based browser compatibility shortcuts and its explicit omission of `Command` + `T`.

This is not a general mapping from conventional browser features to Den Browser. Each shortcut must still fit Den's domain model and interaction semantics; `Command` + `T` creates a Board in the established placement, while `Command` + `R` acts on the Current Sheet.
