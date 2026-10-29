# Performance benchmarking

Use these measurements to investigate startup time and resource use. They are
diagnostic measurements, separate from the correctness checks in interaction
tests.

## Input source restoration timing

Launch a development build with tracing enabled, then move between Boards
with **Remember input method per Board** enabled:

```sh
just build
".derived-data/Build/Products/Debug/Den Browser.app/Contents/MacOS/Den Browser" --benchmark > /tmp/den-input-source.log 2>&1
```

Aggregate the recorded calls without launching another app:

```sh
swift scripts/measure.swift --input-source-log /tmp/den-input-source.log
```

Results group calls by whether the current Carbon input source ID matched the
requested ID before restoration (`same`, `different`, or `unknown`). Each group
reports count, total, average, nearest-rank p95, and maximum elapsed milliseconds.
`restore` covers the whole restoration, `context` covers acquiring the AppKit
input context and setting its source, and `carbon` covers `TISSelectInputSource`
when called. The stage times are included in `restore`; do not sum them with it.
`contextLookup` measures acquiring `NSTextInputContext.current`, and
`contextSelect` measures setting `selectedKeyboardInputSource` when a context
exists. Both are included in `context`. Older logs omit these two fields and
are still accepted by the summary script.
Stages skipped because the current source already matches are recorded as
`none` and excluded from that stage's call count and duration statistics.
These are synchronous call durations on the main thread, including any OS waits,
not isolated XPC wait times. Logging occurs after timing ends. Input source IDs
are not written to the trace. Only completed calls produce a duration record;
no measurements does not mean zero-cost restoration. Stop the traced app before
relaunching it normally.

Restoration selects the source directly through Carbon. The AppKit stage fields
are retained as `none` so logs can be compared with the previous path using the
same summary command. `status` records the Carbon return code (`0` is success),
and `restored` records whether the current input source matches the requested
source after the call. Both are `none` when no Carbon call was made. A matching
source ID does not verify composition or delivery of the next typed character.

## Board facing capture timing

Launch a development build with performance tracing enabled:

```sh
just build
".derived-data/Build/Products/Debug/Den Browser.app/Contents/MacOS/Den Browser" --benchmark > /tmp/den-facing.log 2>&1
```

Move focus until a Terminal or Web Board leaves the viewport. Inspect the log
from another terminal with `rg 'PERF:FACING' /tmp/den-facing.log`.
Each attempted capture logs its Board ID and `duration` in milliseconds.
Skipped captures produce no timing; successful captures suppress recapture of
the same Board for 30 seconds.

`terminal synchronous` measures synchronous capture and scheduling of cache
publication; it excludes the deferred cache publication itself. `web elapsed`
measures the snapshot request through the asynchronous snapshot wait and
cache publication, including failed or discarded snapshot results. Web elapsed
time is not main-thread blocking time.

In Instruments, use the Points of Interest track for subsystem
`dev.nekonata.denbrowser`, category `Performance`. The intervals are
`BoardFacingCapture.terminal`, `BoardFacingCapture.web`, and
`ScreenshotCapture.cacheDisplay` (the synchronous Terminal drawing call).
The last interval also covers explicit Terminal screenshots. Timing excludes
diagnostic log output. Stop the traced app before relaunching it normally.

## XCTest launch metric

The `Den_BrowserUIPerformanceTests` class measures launch with XCTest's
`XCTApplicationLaunchMetric`; it is separate from the default interaction test
class. Run it explicitly and inspect the result bundle:

```sh
just test ui Den_BrowserUIPerformanceTests/testApplicationLaunchPerformance
xcrun xcresulttool get test-results metrics --path <path-to-xcresult>
```

## Board Strip hitch metric

`Den_BrowserUIPerformanceTests/testBoardStripScrollHitches` measures a native horizontal
swipe using `XCTHitchMetric`. It uses the local `rapidBoardFocus` fixture, Den Mode
and Standard Motion. Launch, initial page loading, a warm-up swipe, position checks
and Focused Board centering resets are outside the measured interval. Five measured
iterations report metrics in the result bundle; no regression baseline is configured.

Run on the same Mac/display configuration with no competing UI tests or profiling tools.
The window must be narrow enough for the fixture Boards to overflow. Window and Strip
frames and OS version are attached to the result; compare only matching geometry and
display configurations. The test rejects window-size changes during measurement.
This is a diagnostic performance test, separate from the default interaction test class.

```sh
just test ui Den_BrowserUIPerformanceTests/testBoardStripScrollHitches Release
xcrun xcresulttool get test-results metrics --path .derived-data-ui/TestResults.xcresult
```

The native scroll/render boundary requires a UI performance test; unit layout tests
cannot observe hitches. The test also checks that each measured swipe moves the Strip
and that resetting restores the starting position, so a no-op gesture cannot look fast.

## Scenario benchmark

```sh
just benchmark <scenario>
```

Scenarios are `empty-desk`, `one-terminal-board`, and `one-web-board`. The Web
Board uses a bundled local Sheet fixture. Each run creates a fresh ephemeral
Profile and isolated Desk fixture, and does not read or modify the Personal
Profile. Terminal Boards use `/bin/zsh -f` without the user's Ghostty
configuration. Each run uses an isolated socket at
`<temporary-directory>/den-benchmark-<runID>.sock`.

Measurement options follow `--`; defaults are a 4-second settle phase, a
10-second idle phase, and 1-second sample intervals:

```sh
just benchmark one-web-board -- --duration 20
```

Settle and idle durations must be finite and non-negative; the sample interval
must be finite and greater than zero.

The benchmark opens a new app instance through Launch Services. Startup ends
when the Profile window is presented; for `one-web-board`, it also waits for the
Sheet navigation and a reported WebKit process ID. It then samples post-ready
settle and post-settle idle as separate phases.

CPU percentages use process CPU-time deltas between snapshots. RSS is read from
each process snapshot. Startup CPU sampling uses a prelaunch baseline; RSS
sampling starts when the app PID is available. WebKit metrics include only PIDs
reported by Board runtimes. They can be `N/A` before a WebKit PID is reported or
after that process exits. The number of active WebKit runtimes can vary with
which Boards are in the viewport.
