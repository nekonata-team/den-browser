# Swift import checks

Run `just architecture-check` to test the rules and scan the application and all
three package source roots: `DenDomain`, `DenDesign`, and `DenIPCProtocol`.
`just lint` and `just check` also run this check. The ast-grep version is pinned in
`mise.toml` so parser changes are reviewed together with the rule fixtures.

- Domain excludes SwiftUI, AppKit, WebKit, and GhosttyTerminal imports. This rule
  scans app Domain files and every source under `Packages/DenDomain/Sources`.
- `DenDesign` sources are included in formatting and architecture scans; SwiftUI is
  expected there because the package owns shared presentation components.
- `DenIPCProtocol` may import Foundation only. Its wire DTOs do not depend on app,
  Domain, or UI modules.
- Application excludes SwiftUI imports. Native AppKit integration remains allowed.

Application rules apply by source layer, including nested Board features. The checks
do not enumerate project types or prohibit all references between app Features.

These are import guards, not a compiler-resolved dependency graph. Swift packages
enforce their module boundaries; behavioral tests should verify lifetime, event
destinations, and shared-state consistency. Passing this scan does not prove isolation
between app source groups.
No automatic fixes are configured.

Rule fixtures include permitted imports, forbidden imports, qualified and
attributed imports, and comments/strings. Snapshot output is not part of
the contract, so the recipe uses `ast-grep test --skip-snapshot-tests`.
