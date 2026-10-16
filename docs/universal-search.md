# Universal Search

Universal Search is a window-local palette shared by the toolbar Search button, `Command-P`, and Den Mode's `:`.
`Command-Shift-P` prefills `> `. A leading `>` limits results to commands; removing it returns
to all results. Escape dismisses the palette without changing Den Mode. Up/Down select a result and Return runs
its displayed action. Option-Return or Option-click opens a URL, search, or Essential in Drawer; navigation results and commands
show a validation message instead. The palette stays open when the input cannot be opened in Drawer. IME composition retains native editing keys instead of executing a result.

## Foundation scope

- Search Board labels, Current Sheet URLs, Terminal working directories, and Zellij/zmx session names in the current Profile.
- Switch to a Desk in the current Profile or open/activate a Profile window by Profile name.
- Paste a full Board, Desk, or Profile UUID from CLI output to find an exact ID match, case-insensitively.
  Board and Desk ID search stays within the current Profile; Profile ID search uses the Profile list.
- Search Essential names, keys, and inputs; selecting an Essential creates a Board in the current Desk.
- Search all Recent titles and inputs in the current Profile, showing at most five matches.
  Selecting a Recent Item creates another Board in the current Desk.
- Open a URL, local path, web search, or existing `:terminal`, `:tutorial`, `:zellij`, and `:zmx` Board input.
- Run New Desk, Open Profile, Open Settings, Toggle Zen View, Toggle Focus Mode, and Restore Recently Removed Board.
  Restoration is offered only when a removed Board is available.

With empty input, display Recent (the five newest items), Essentials, Boards, Desks, Profiles, then commands.
Boards include all Desks in the current Profile, preserving Desk and Board order.

Boards, Essentials, and Recent are separate candidates even when names or URLs match. Creation is always
an explicit candidate, even when a Board matches. With input, ordering is Boards, Essentials, Desks,
Profiles, commands, Recent, then creation. Exact UUID matches precede metadata matches, keeping their source order.
Metadata matches and the creation candidate remain available; partial IDs do not match by ID.
Each whitespace-separated search term must match candidate metadata,
case-insensitively. Query changes select the first available result; a removed selection falls back to an available
result. Recent matches prioritize exact title or input matches, then preserve most recent use order.
This foundation does not provide fuzzy ranking or learned usage ranking.

## Extension points

Cross-Profile Board/Desk search, page-body and Terminal-output search, Board relocation, and parameterized command
workflows are outside this foundation. Searches do not instantiate runtimes or open other Profiles merely to
enumerate candidates. Profile activation uses the existing window registry.

Query, selection, and candidate metadata are transient, with no preference or persisted Profile schema.
