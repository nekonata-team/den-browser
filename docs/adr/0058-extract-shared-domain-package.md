---
status: accepted
---

# Extract shared Domain types into one package

Selected Foundation-only Domain values are compiled in one `DenDomain` Swift package
target and imported directly by the app and unit-test targets. Keeping the connected
model closure in one module preserves its cross-feature references while giving those
types a compiler-enforced dependency boundary. Feature behavior, persistence adapters,
and runtime integration remain in the app target. The module's source ownership and
dependency rules are described in the [architecture guide](../architecture.md#dependency-direction).
