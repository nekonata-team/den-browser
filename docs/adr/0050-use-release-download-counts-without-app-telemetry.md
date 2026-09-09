---
status: accepted
---

# Use Release Download Counts Without App Telemetry

Den Browser does not introduce app usage telemetry or automatic crash-report uploads. Understanding adoption, feature use, and failures would help development, but the current need does not justify changing the [published no-telemetry policy](../../web/src/pages/privacy.md), asking users to evaluate diagnostic data, or operating a collection pipeline. This decision applies to both opt-out and opt-in collection; an in-app crash-report submission flow remains deferred.

Use GitHub Release asset [`download_count`](https://docs.github.com/en/rest/releases/releases) values for the distributed app archives as a coarse distribution indicator. These are download counts, not installations, unique users, or active users. Repeat downloads and updates can contribute to the counts; the [release workflow](../releasing.md) also directs Sparkle updates to the Release ZIP, so new downloads cannot be separated from updates using these counts. They reveal neither feature use nor retention, and cannot establish a crash rate. Tracking changes over time would require periodic snapshots; this decision does not add collection automation.

Accept these measurement limits and use voluntarily shared bug reports to investigate failures and guide regression coverage. Reconsider app-side collection only when a concrete quality or development decision cannot be addressed through those reports and distribution counts, with a separate decision on data scope, user choice, recipients, and retention before implementation.
