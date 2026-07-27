---
status: accepted
---

# Support deliberate downloads without managing them

Den Browser supports deliberate file downloads from a Current Sheet. File downloads are intermittent but ordinary parts of long-running web work. Requiring another browser whenever a site provides a file would interrupt that work and conflict with Den Browser's purpose as a companion for sustained web tasks.

Supporting downloads does not make Download management part of the Den work model. Each download uses the macOS save panel with the filename suggested by the site. Den Browser reports completion or failure, but does not provide an automatic destination, history, progress UI, or resume support. A Download is not a Den, Desk, Board, or Sheet concept and is not persisted in `DenState`.

The app remains sandboxed. It grants read-write access only to a destination the user selects through the save panel. Replacing an existing file requires the panel's normal confirmation.

`BoardRuntime` owns the live `WKDownload` integration because the download inherits the Current Sheet's WebKit session and ends with that runtime interaction. The download destination and lifecycle do not enter persisted Profile or Den state.

This decision narrows the download exclusion in [ADR 0001](./0001-companion-browser.md). It does not change the `http` and `https` Sheet URL restriction in [ADR 0022](./0022-restrict-sheet-urls-to-http-and-https.md): downloading a file is distinct from navigating a Sheet to a local `file://` URL.
