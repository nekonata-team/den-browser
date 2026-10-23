# Separate Views from native Runtime ownership

Views depend directly on presentation Models and Domain; Models may retain concrete Application operations privately and accept them through public construction initializers. There is one Model / VM target, `DenModels`, with no display SDK dependencies. App composition supplies existing AppKit views directly to native display adapters in `DenViews`; the app-owned WebKit/Ghostty implementations retain Runtime, private-header, and resource responsibilities. This keeps view attachment and display at the View boundary and leaves pure Model tests independent of native SDKs.

The existing Profile Store remains authoritative. Window composition owns screen Models and display connections. `DenBoardRuntimes` owns Profile-shared runtimes and one `BoardRuntimeReceiver` per Board. The receiver references Profile resources weakly and updates shared Application operations directly. Runtime callbacks retain a `RuntimeWindowConnection` with weak references to focused native adapters and explicit window inputs. Closing the window explicitly disconnects those destinations, including download presentation, while shared events continue reaching the Profile Store.

| Resource | Strong owner | Release / disconnect |
| --- | --- | --- |
| Board Runtime and event receiver | Profile's `DenBoardRuntimes` | Board disposal or final Profile-window teardown |
| Native event window connection | Window and Runtime callbacks | Window close disconnects; Runtime disposal clears callbacks |
| Drawer Peek | Invoking window's `DenWindowResources` | Close/replacement disposes; successful placement transfers the same Runtime to the Profile registry |
| Screenshot and zmx operation Tasks | Window resources | Window close or operation replacement cancels; late results are rejected |
| Inspection presentation and child loads | Mounted Inspection Model | View disappearance/navigation cancels loads; stale page results are rejected |

Native Runtime/DOM/Terminal implementations remain App-owned and do not depend on screen Models. App composition observes their native state and supplies existing NSViews, live pure values and actions to `DenViews`. This does not add a second Model target or change Runtime lifetimes.

This updates the Model dependency restriction in [ADR 0062](0062-profile-state-source-and-presentation-models.md); it does not move native execution into a screen Model or change persisted state.

Drawer and temporary-panel overlays also live in DenViews. App supplies their concrete content and native callbacks. Board Activity process sampling stays in its app-target Infrastructure and follows the mounted panel’s cancellation lifetime; rendering receives sampled values and observed native status. Native mounting tests use the production View adapter directly.
