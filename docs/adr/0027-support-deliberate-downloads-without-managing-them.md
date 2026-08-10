---
status: accepted
---

# Support deliberate downloads without managing them

Den Browser supports deliberate file downloads from a Current Sheet. File downloads are intermittent but ordinary parts of long-running web work. Requiring another browser whenever a site provides a file would interrupt that work and conflict with Den Browser's purpose as a companion for sustained web tasks.

Supporting downloads does not make Download management part of the Den work model. Each download uses the macOS save panel with the filename suggested by the site. Den Browser reports completion or failure, but does not provide an automatic destination, history, progress UI, or resume support. A Download is not a Den, Desk, Board, or Sheet concept and is not persisted in `DenState`.

The app is unsandboxed per [ADR 0032](./0032-embed-terminal-boards-with-libghostty.md). Downloads still use a destination the user explicitly selects through the save panel, and replacing an existing file requires the panel's normal confirmation.

`BoardRuntime` owns the live `WKDownload` integration because the download inherits the Current Sheet's WebKit session and ends with that runtime interaction. The download destination and lifecycle do not enter persisted Profile or Den state.

This decision narrows the download exclusion in [ADR 0001](./0001-companion-browser.md). [ADR 0033](./0033-support-local-file-sheet-urls.md) later permits local `file://` Sheets, but downloads remain distinct: their destinations and lifecycle do not enter persisted Den state.
