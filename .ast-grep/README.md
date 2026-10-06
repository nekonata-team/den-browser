# Swift import checks

Run `just architecture-check` to test the rules and scan the application sources.
`just lint` and `just check` also run this check. The ast-grep version is pinned in
`mise.toml` so parser changes are reviewed together with the rule fixtures.

- Domain excludes SwiftUI, AppKit, WebKit, and GhosttyTerminal imports.
- Application excludes SwiftUI imports. Native AppKit integration remains allowed.

Rules apply by source layer, including nested Board features. They do not enumerate
project types or prohibit all references between Features.

These are import guards, not a compiler-resolved dependency graph. Module boundaries
should enforce type dependencies; behavioral tests should verify lifetime, event
destinations, and shared-state consistency. A single-target project can still reference
other layers without an import, so passing this scan does not prove layer isolation.
No automatic fixes are configured.

Rule fixtures include permitted imports, forbidden imports, qualified and
attributed imports, and comments/strings. Snapshot output is not part of
the contract, so the recipe uses `ast-grep test --skip-snapshot-tests`.
