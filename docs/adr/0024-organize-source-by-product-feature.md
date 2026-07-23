---
status: proposed
---

# Organize source by product feature

Den Browser organizes source primarily by product feature, with `App` for composition and `Platform` for operating-system integration. A layer-first `Domain`, `UI`, and `Infrastructure` split was rejected because Den workflows deliberately connect persisted state, presentation state, and live WebKit runtime inside one Swift target; forcing those files into global layers would scatter cohesive changes and encourage abstractions that do not enforce a real boundary.

`Den`, `Profiles`, and `SheetNavigation` are top-level Features. Board, Desk, Sheet, and Overview remain nested within the Den Feature because they share its `DenStore`, lifecycle, and invariants; treating them as top-level Features would create conceptual cycles between their UI and Den composition. Vim-style Sheet Navigation is separate because it owns independent preferences and WebKit content interaction, while Den only supplies its controller to each Board runtime. Feature dependencies must form an acyclic graph. A one-way dependency is allowed when a clear product ownership or lifecycle relationship explains it, such as a Profile owning one Den. `App` contains composition and cross-feature orchestration, but feature behavior is not promoted there merely because another Feature uses it.

Feature-specific WebKit, keyboard, and persistence integration remains with its owning Feature or in `App`. Code moves to `Platform` only after a concrete feature-independent boundary emerges; importing an operating-system framework alone is not a reason to create a global layer. Existing reverse dependencies are narrowed when useful during concrete changes rather than as a prerequisite for source organization.
