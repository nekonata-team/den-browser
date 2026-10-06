# Swift import checks

Run `just architecture-check` to test the rules and scan the application and
`DenDomain` package sources.
`just lint` and `just check` also run this check. The ast-grep version is pinned in
`mise.toml` so parser changes are reviewed together with the rule fixtures.

- Domain excludes SwiftUI, AppKit, WebKit, and GhosttyTerminal imports. This rule
  scans app Domain files and every source under `Packages/DenDomain/Sources`.
- Application excludes SwiftUI imports. Native AppKit integration remains allowed.

Application rules apply by source layer, including nested Board features. The checks
do not enumerate project types or prohibit all references between app Features.

These are import guards, not a compiler-resolved dependency graph. The Swift package
enforces the moved Domain types' module boundary; behavioral tests should verify
lifetime, event destinations, and shared-state consistency. Passing this scan does not
prove isolation between app source groups.
No automatic fixes are configured.

Rule fixtures include permitted imports, forbidden imports, qualified and
attributed imports, and comments/strings. Snapshot output is not part of
the contract, so the recipe uses `ast-grep test --skip-snapshot-tests`.
