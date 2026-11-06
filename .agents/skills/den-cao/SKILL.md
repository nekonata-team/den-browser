---
name: den-cao
description: Coordinate Codex or other interactive CLI agents in Den Terminal Boards when delegating work through Den. Covers startup, task submission, reply recovery, and cleanup.
---

# Den CLI Agent Orchestrator

The parent chooses tasks and concurrency. Adapt launch options, input submission, and state detection to each agent.

## Before starting

- Use the `den` skill for targeting and placement, or consult CLI help. If `den` is absent from PATH, use `/Applications/Den Browser.app/Contents/MacOS/den`.
- Check `den health --json` and `den board terminal text --help` for `--lines` support. If unavailable, report the prerequisite failure; do not launch or restart Den automatically.
- Use `--json`. Track each child's returned `.board_id`, task, and status; target it explicitly with `--board`.
- Use the same Profile/socket context throughout, inheriting the caller's unless otherwise requested.
- Honor requested agent settings; otherwise use the current task directory and the agent's configured defaults. Follow repository isolation rules for file edits and preserve the parent's permission boundaries.

## Start and submit

Launch the chosen agent in a Terminal Board. For example:

```sh
den board terminal new <working-directory> --run 'codex --no-alt-screen' --json
```

Confirm options and input submission with the agent's `--help`. Codex's `--no-alt-screen` enables useful scrollback; other agents may use different options. Preserve focus unless requested otherwise.

Read `.text` to check readiness:

```sh
den board terminal text --board <child-board-id> --json
```

Confirm the selected agent has started and accepts input. A created Board may still be starting or showing a shell; never send task text to the shell. Report unreadable or blocked startup at the startup deadline.

Specify the task, file/worktree ownership, expected result, and checks. Tell concurrent writers to preserve others' changes. Submit:

```sh
den board terminal run '<task text>' --board <child-board-id> --json
```

Shell-quote task text safely. `run` pastes text and presses Enter; use it only when that submits a task in the agent. Success acknowledges input, not acceptance or completion. Inspect for existing drafts, ongoing work, or approval/question dialogs before sending.

## Observe and recover

- Set startup and task deadlines. Read at spaced intervals; on expiry, report observed state and possible delivery. Slow responses, ambiguous state, or read failures are not reasons to resubmit.
- Judge progress from activity, new reply text, and completion indicators together. Input-looking footers may remain during generation; ambiguous state stays unconfirmed.
- Relay approval/clarification requests with the child ID; do not automatically approve them.
- Recover the reply from history, increasing N if its beginning is missing:

```sh
den board terminal text --board <child-board-id> --lines 200 --json
```

`--lines N` reads retained history beyond the viewport. Separate the assigned task's reply from echoed prompts, tool output, previous turns, and UI chrome.

Cleared, overwritten, evicted, or application-owned history may be unavailable. If increasing N stops revealing needed content, report incomplete recovery. Claim success only after recovering the result and checking the task's completion criteria.

For follow-ups, check readiness again and track the new task separately.

## Finish

Report each child's result, checks, and unresolved state or missing output. Keep Boards needed for inspection; otherwise close owned Boards after recovering their results:

```sh
den board close --board <child-board-id> --json
```

Closing terminates live activity. Do not close unrelated Boards or working children merely because a wait expired.
