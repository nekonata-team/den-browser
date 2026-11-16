# Unit Testing

## Admission rule

Add a unit test only when all three hold (name the contract and why static checks or extending an existing test are insufficient):

- Protects a risk-bearing contract: persistence/migration integrity, external boundaries (IPC, CLI, MCP, URL/link resolution, preference schemas), non-trivial state transitions/invariants, keyboard routing, or resource/cancellation lifetime.
- Static checks (Swift types, compiler warnings, SwiftLint, `ast-grep`) cannot catch the failure.
- No existing test covers the same contract and failure mode.

Do not add (and treat existing ones as removal candidates):

- Trivial property storage, pass-through wrappers, defaults, or compiler-synthesized `Codable` round-trips (test `Codable` only for custom coding logic or fixed legacy/schema fixtures).
- Implementation details (mock call counts, internal call order, `Task` identity).
- Exhaustive edge cases on low-impact features (e.g., tutorial progress, auxiliary UI state); keep at most one representative test.
- Duplicate input-permutation scenarios; parameterize or merge into one test.

## Boundaries & structure

| Target | Contract |
| --- | --- |
| Domain / Application | Actor-independent rules, decisions, state transforms, shared workflows (`Application` tests are `nonisolated`) |
| Models | Live Observation, shared/window-local state, transitions, cancellation |
| Infrastructure | Filesystem/bitmap I/O, OS process sampling |
| App | Native SDK/resource connections, Profile/window lifecycle, UI/IPC integration |

- Test each component through its own interface; avoid constructing an outer app graph.
- Group tests by responsibility with one narrow contract per file; split oversized suites rather than appending unrelated scenarios.
- Layout: `Board/Web`, `Board/Terminal`, `Board/Inspection`; helpers in `Support`; resources in `Fixtures`. Do not mirror source folders.
- Structure each test with `// Arrange`, `// Act`, `// Assert`; isolate preferences from `UserDefaults.standard`.
- Verify package contract coverage and safe test pruning with [mutation testing](./mutate.md) (`just test mutate` or `just test mutate <path>`).
