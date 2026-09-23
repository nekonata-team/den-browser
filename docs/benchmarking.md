# Performance benchmarking

Use these measurements to investigate startup time and resource use. They are
diagnostic measurements, separate from the correctness checks in interaction
tests.

## XCTest launch metric

The `Den_BrowserUIPerformanceTests` class measures launch with XCTest's
`XCTApplicationLaunchMetric`; it is separate from the default interaction test
class. Run it explicitly and inspect the result bundle:

```sh
just ui-test Den_BrowserUIPerformanceTests/testApplicationLaunchPerformance
xcrun xcresulttool get test-results metrics --path <path-to-xcresult>
```

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
