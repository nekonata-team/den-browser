# Demo videos

Run from the repository root in a macOS terminal with Screen Recording and
Accessibility permissions. Install the pinned tools with `mise install` first.
Peekaboo needs both permissions; OpenScreen needs Screen Recording permission.

```sh
just demo
just pv
just pv /path/to/video.mp4
```

`demo` builds the app and replays a mouse-led workflow: collect the product site
and repository on Research, create Build, open a Terminal Board at home, run
`echo hello`, and duplicate the Terminal through its Header context menu.
Create a Gemini Desk from its three-Board preset.
`Control+,` enters Den Mode; Right, Right, Left focuses successive Gemini Boards
and finishes on the middle Board. Finally, `w`, `3` fits three columns in the window.
In Overview, two Up presses select Research; double-clicking the product Board enters it.
Text is entered briefly; Return submits fields and the terminal command.

`pv` records the same Demo window and exports `demo.mp4` and an editable
`demo.openscreen`, or the supplied MP4 path and its matching project path.
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
