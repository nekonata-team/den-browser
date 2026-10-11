# Universal Search

Universal Search is a window-local palette shared by the toolbar Search button, `Command-P`, and Den Mode's `:`.
`Command-Shift-P` opens it with `> ` already entered. A leading `>` limits results to commands; removing it returns
to all results. Escape dismisses the palette without changing Den Mode. Up/Down select a result and Return runs
its displayed action. IME composition retains native editing keys instead of executing a result.

## Foundation scope

- Search Board labels, Current Sheet URLs, Terminal working directories, and Zellij/zmx session names in the current Profile.
- Switch to a Desk in the current Profile or open/activate a Profile window by Profile name.
- Search Essential names, keys, and inputs; selecting an Essential creates a Board in the current Desk.
- Open a URL, local path, web search, or existing `:terminal`, `:tutorial`, `:zellij`, and `:zmx` Board input.
- Run New Desk, Open Profile, Open Settings, Toggle Zen View, Toggle Focus Mode, and Restore Recently Removed Board.
  Restoration is offered only when a removed Board is available.

Existing Boards and Essentials remain separate candidates even when their names or URLs match. Creation is always
an explicit candidate, including when an existing Board matches. Current ordering is Boards, Essentials, Desks,
Profiles, commands, then creation. Each whitespace-separated search term must match candidate metadata,
case-insensitively. Query changes select the first available result; a removed selection falls back to an available
result. This foundation does not yet provide fuzzy ranking or usage history.

## Extension points

`UniversalSearchModel` owns query filtering and selection over typed candidates without UI or runtime objects.
`UniversalSearchActions` supplies candidate metadata and dispatches selected targets to existing application operations.
Adding another search source does not require another keyboard entrance or panel.

Cross-Profile Board/Desk search, page-body and Terminal-output search, Board relocation, and parameterized command
workflows are outside this foundation. Searches do not instantiate runtimes or open other Profiles merely to
enumerate candidates. Profile activation uses the existing window registry.

Query, selection, and candidate metadata are transient. No preference or persisted Profile schema is added.
