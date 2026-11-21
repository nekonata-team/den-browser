# Universal Search

Universal Search is a window-local palette shared by the toolbar Search button, `Command-P`, and Den Mode's `:`.
`Command-Shift-P` prefills `> `. A leading `>` limits results to commands; removing it returns
to all results. Escape dismisses the palette without changing Den Mode. Up/Down select a result and Return runs
its displayed action. Option-Return or Option-click opens a URL, search, supported Terminal command, or Essential in Drawer; navigation results and application commands
show a validation message instead. The palette stays open when the input cannot be opened in Drawer. IME composition retains native editing keys instead of executing a result.

## Foundation scope

- Search Board labels, Current Sheet URLs, Terminal working directories, and Zellij/zmx session names in the current Profile.
- Switch to a Desk in the current Profile or open/activate a Profile window by Profile name.
- Find Drawer Items in the current Den by name, URL, Terminal working directory, or session name.
  Return opens the Item's Drawer Peek without placing it on a Desk.
- Create a Desk from a Built-in or Personal Desk Preset.
- Paste a full Board, Desk, or Profile UUID from CLI output to find an exact ID match, case-insensitively.
  Board and Desk ID search stays within the current Profile; Profile ID search uses the Profile list.
- Search Essential names, keys, and inputs; selecting an Essential creates a Board in the current Desk.
- Search all Recent titles and inputs in the current Profile, showing at most five matches.
  Selecting a Recent Item creates another Board in the current Desk.
- Open a URL, local path, web search, or existing `:terminal`, `:tutorial`, `:zellij`, and `:zmx` Board input.
- Run New Desk, Open Profile, Open Settings, Toggle Zen View, Toggle Focus Mode, Undo Board Operation,
  and Show Keyboard Shortcuts. Undo is offered only when the Board Undo history is nonempty.
  Command rows show the keys and input mode for invoking the action outside the palette.
  Search `> shortcuts` to open the Keyboard Shortcuts guide.

With empty input, display Recent (the five newest items), Essentials, Boards, Desks, Desk Presets, Profiles,
Drawer Items, then commands.
Boards include all Desks in the current Profile, preserving Desk and Board order.

Boards, Essentials, and Recent are separate candidates even when names or URLs match. Creation is always
an explicit candidate, even when a Board matches. With input, exact UUID matches come first, followed by
exact title matches, title prefix matches, titles containing all terms, and other metadata matches.
Ties keep their source order. Recent and the creation candidate come last.
Metadata matches and the creation candidate remain available; partial IDs do not match by ID.
Each whitespace-separated search term must match candidate metadata,
case-insensitively. Query changes select the first available result; a removed selection falls back to an available
result. Recent matches prioritize exact title or input matches, then preserve most recent use order.
Terminal Boards, Essentials, and Recent Items match both command names and their aliases (`:terminal` / `:term`,
`:zellij` / `:zj`, and `:zmx` / `:x`).
This foundation does not provide fuzzy ranking or learned usage ranking.

## Implementation map

- Search candidates, matching, and ranking: [`UniversalSearch.swift`](../Packages/DenDomain/Sources/DenDomain/Den/UniversalSearch.swift).
- Result rows and shortcut hints: [`UniversalSearchPanel.swift`](../Packages/DenViews/Sources/DenViews/Den/UniversalSearchPanel.swift).
- Result execution and the actions behind shortcut hints: [`UniversalSearchActions.swift`](../Den%20Browser/Den%20Browser/Features/Den/Application/UniversalSearchActions.swift).
- Key bindings: [`KeyboardRouting.swift`](../Den%20Browser/Den%20Browser/App/KeyboardRouting.swift) for routed shortcuts; [`Den_BrowserApp.swift`](../Den%20Browser/Den%20Browser/App/Den_BrowserApp.swift) and [`DenHeader.swift`](../Packages/DenViews/Sources/DenViews/Profiles/DenHeader.swift) for the native Open Profile shortcut.

## Extension points

Cross-Profile Board/Desk search, page-body and Terminal-output search, Board relocation, and parameterized command
workflows are outside this foundation. Searches do not instantiate runtimes or open other Profiles merely to
enumerate candidates. Profile activation uses the existing window registry.

Query, selection, and candidate metadata are transient, with no preference or persisted Profile schema.
