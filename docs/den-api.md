# Den JavaScript API

Local HTML can opt into a bundled `window.den` API. No package install, script tag, or local server is required.
The first API is `den.boards.focus(boardId: string): Promise<void>`, which focuses an existing Board in the same Profile without activating its window.
It rejects invalid IDs, missing Boards, unavailable navigation, and unauthorized callers.

## Enable and disable

```sh
den board web new /tmp/report.html --den-api --json
den board web reload --board <id> --den-api --json
den board web reload --board <id> --no-den-api --json
```

`new --den-api` enables the Board's API setting when opening a local `.html` or `.htm` file.
`reload --den-api` enables the Board's API setting from a local HTML Current Sheet.
`reload --no-den-api` disables it. The two reload flags are mutually exclusive.
Reload without either flag preserves the setting. Enabling on a remote URL or non-HTML file fails without changing settings.

The enabled flag belongs to the Board and persists across app restarts. No API-specific file URL is stored.
All local HTML files opened in that Board can use the API, including links to other local HTML files.
Remote pages and non-HTML files cannot use it. Returning to local HTML restores access without changing the flag.
Another Board opening the same file starts disabled.

## Author HTML

Den injects the API at document start in local HTML main frames of an enabled Board. Inline scripts can use it immediately.

```html
<button id="back">Return to related Board</button>
<p id="error" role="status"></p>
<script>
  document.getElementById('back').onclick = async () => {
    try {
      await den.boards.focus('REPLACE-WITH-BOARD-UUID');
    } catch (error) {
      document.getElementById('error').textContent = String(error);
    }
  };
</script>
```

Discover Board IDs through `den board list`; use full UUIDs. These calls use existing native Board operations and do not invoke an AI model.
The TypeScript contract is [DenAPI](../scripts/embedded-js/src/den-api/entry.ts).

## Scope

Native handlers validate the owning WebView, enabled flag, main frame, local HTML URLs, action, and arguments on every call.
Direct calls from iframes and popup WebViews are rejected. Scripts loaded by the enabled main document share its access;
same-origin frames with access to the parent window can also use the parent's API, following normal browser rules.
The API does not expose arbitrary shell execution, the CLI transport, or the filesystem.
It is available in Den only; ordinary browsers do not supply `window.den`.

Disabling revokes calls immediately, including functions retained by the old page, and reloads the Current Sheet.
If saving a reload setting fails, the current session retains the intended change and the command reports an error, following Den's persistence contract.
