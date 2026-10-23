# Swift source checks

Run `just architecture-check` to scan the application and all
package source roots: `DenDomain`, `DenIPCProtocol`, `DenApplication`, `DenModels`, `DenViews`, and `DenInfrastructure`.
Run `just test architecture` to test the rule definitions against their fixtures.
`just lint` and `just check` also run `architecture-check`. The ast-grep version is pinned in
`mise.toml` so parser changes are reviewed together with the rule fixtures.

- Domain excludes SwiftUI, AppKit, WebKit, and GhosttyTerminal imports. This rule
  scans every source under `Packages/DenDomain/Sources`.
- `DenViews` owns shared presentation components and Feature Views; SwiftUI is
  expected there. Pure Models cannot import Views or drawing SDKs.
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

App-owned corners use `DenRadius` instead of literal `cornerRadius` arguments in
Feature and DenViews sources. Geometry-derived expressions remain allowed.
In the same sources, `RoundedRectangle` and `.rect` reject `style: .circular`;
omit the style or use `.continuous`.

App unit/UI tests and package `Tests` sources reject explicit `UserDefaults.standard`
access, including `Foundation.UserDefaults.standard`. Use isolated suites or test containers.

Rule fixtures include permitted imports, forbidden imports, qualified and
attributed imports, and comments/strings. Snapshot output is not part of
the contract, so the recipe uses `ast-grep test --skip-snapshot-tests`.

`DenApplication` allows Foundation, Observation, and DenDomain only; native/UI frameworks
and Presentation dependencies are excluded. Pure `DenModels` allows Foundation, Observation,
DenApplication, and DenDomain. `DenViews` allows Domain and the single Model module,
and drawing SDKs/libraries enumerated in `views-imports.yml`; it rejects Application and the app. Package
manifests enforce the same dependency direction. `model-no-operation-exposure` rejects public exposure of Application operation types and the write
capability from Model properties, functions, subscripts, and type aliases, including public extensions.
Construction initializers may receive them; private storage and method-body use remain allowed.
Its explicit capability names complement import guards and package visibility; it is not type resolution.
App composition supplies live read inputs and focused native callbacks. Native implementations
remaining in the app target are still protected only by layer checks, not a separate module.

`DenModels` rejects AppKit and native SDK imports. Native display adapters belong
to `DenViews`; composition supplies their existing AppKit views without exposing Runtime types.

`DenInfrastructure` currently allows DenDomain, Foundation, and OS diagnostics only. Persistence and diagnostics cannot import app or Presentation code.
