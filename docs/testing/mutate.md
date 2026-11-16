# Mutation Testing

[`scripts/mutate.swift`](../../scripts/mutate.swift) verifies that package unit tests detect behavioral regressions in risk-bearing logic and prevents accidental coverage loss when pruning redundant tests.

## Mutation operators

Mutations are discovered with `ast-grep` and applied one at a time in place (restoring the original file atomically after each test run and on `SIGINT`/`SIGTERM`):

| Category | Original | Mutated | AST scope |
| --- | --- | --- | --- |
| Equality | `==`, `!=` | `!=`, `==` | `equality_expression`, `infix_expression` |
| Comparison | `<`, `<=`, `>`, `>=` | `<=`, `<`, `>=`, `>` | `comparison_expression`, `infix_expression` |
| Logical | `&&`, `\|\|` | `\|\|`, `&&` | `conjunction_expression`, `disjunction_expression`, `infix_expression` |
| Prefix negation | `!expr` | `expr` (`!` removed) | `bang` inside `prefix_expression` |
| Boolean return | `return true`, `return false` | `return false`, `return true` | `boolean_literal` inside `control_transfer_statement` |

Skipped lines: diagnostics and previews (`Logger`, `os_log`, `PerformanceTrace`, `print(`, `debugDescription`, `#Preview`) and `.sorted` comparator closures.

## Scope & test routing

- Supported targets (`Packages/<Package>/Sources/**/*.swift`): `DenDomain`, `DenIPCProtocol`, `DenInfrastructure`, `DenApplication`, `DenModels`.
- Each package runs `swift test --package-path Packages/<Package>`. `DenApplication` sources route to `DenApplicationTests` or `DenModelsTests` when a matching `<Basename>Tests.swift` exists in only one package, or run both otherwise.

## Usage & outcomes

```sh
just test mutate
just test mutate Packages/DenDomain/Sources/DenDomain/Web
just test mutate --strict Packages/DenDomain/Sources/DenDomain/Web/WebURLPolicy.swift
```

- **Diff mode** (no path arguments): mutates only added or modified lines in `Packages/*/Sources` (`git diff HEAD`, falling back to `main...HEAD` when the working tree is clean).
- **Target mode** (one or more file or directory paths): mutates all supported Swift source files at or under the specified paths.
- **`--strict`**: exits with status `1` when any mutant survives. By default, the runner exits `0` after reporting survivors so equivalent mutants (such as `<` vs `<=` on an already-guarded boundary) can be inspected without failing local checks.
- **Outcomes**: `KILLED` (at least one test failed), `SURVIVED` (all mapped tests passed — either a missing test assertion or an equivalent mutant), `SKIPPED` (mutation failed to compile; excluded from the kill-rate denominator).
