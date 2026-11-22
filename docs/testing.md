# Testing

1. **Static checks first**: Swift types, compiler warnings, SwiftLint, and [source guards](../.ast-grep/README.md).
2. **[Unit testing](./testing/unit.md)** & **[mutation testing](./testing/mutate.md)**: Risk-bearing state, boundary, and contract rules.
3. **[UI testing & exploratory validation](./testing/ui.md)**: Native UI boundaries (`XCUITest`, [ADR 0020](./adr/0020-test-critical-ui-workflows.md)) and environment-dependent checks.

- [Den `read` case register](./testing/den-read.md): manual checks on live sites.
- Commands: see [test.just](../test.just) for test recipes and [justfile](../justfile) for `check`/`lint`.
- Performance measurement: see [benchmarking.md](./benchmarking.md).
