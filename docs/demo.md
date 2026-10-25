# Demo videos

Run from the repository root in a macOS terminal with Screen Recording and
Accessibility permissions. Install the pinned tools with `mise install` first.
Peekaboo needs both permissions; OpenScreen needs Screen Recording permission.

```sh
just demo                  # run default (promotional) scenario
just demo run agent-verify # run a specific scenario
just demo pv               # record promotional to demo.mp4
just demo pv agent-verify  # record a specific scenario
```

`demo` and `demo pv` support four scenarios: `promotional` (default), `agent-verify`, `agent-desk`, and `agent-show-me`.
- `promotional`: replays a mouse-led workflow across Research, Build, Gemini presets, and Den Mode.
- `agent-verify`: demonstrates human-AI agent cooperation with side-by-side Terminal and Web Boards, executing `den board web snapshot` and semantic tree click actions.
- `agent-desk`: demonstrates background Desk deployment via `den desk list` and `den board web new --desk`, preserving the human's active workspace and inspecting collected material via tab click.
- `agent-show-me`: demonstrates visual diagram delivery via `den board web new`, presenting instant architecture and design boards adjacent to the agent's Terminal.

`demo pv` records the demo window, exports `demo.mp4` and its editable `demo.openscreen`, and optimizes the video for web delivery.
OpenScreen generates zooms from recorded clicks at export, without hand-authored
zoom regions. Den Mode captions, cursor smoothing, click bounce, and a 16:9 frame
are included. Re-export with
`openscreen export video.openscreen -o video.mp4 --auto-zoom`;
in the editor, run Automatic zooms before exporting.
Existing videos and projects are rejected rather than overwritten.
The screen must remain unlocked; avoid using the keyboard and mouse during a take.
The script selects the ABC keyboard input source before the scenario and restores
the previous source on exit, including scenario errors. ABC must be available.

Each run launches its own app process with a fresh Demo Profile, preferences,
and nonpersistent website data. The Demo uses When Overflowing Board centering
and Standard Motion, independent of the system's Reduce Motion preference.
It closes that process and removes its temporary
Profile and preferences when finished. Normal Profiles are not used.
OpenScreen keeps source recordings in its own recordings directory.

Permission or scenario failures stop the command with an error. Grant permissions
to the executable or terminal that actually runs the scenario; an agent's background
process can have different permissions from the terminal displaying the conversation.
