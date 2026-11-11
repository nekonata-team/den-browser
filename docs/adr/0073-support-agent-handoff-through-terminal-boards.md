---
status: accepted
---

# Support Agent Handoff Through Terminal Boards

Den provides a visible place to hand off a task by launching a CLI agent with an initial task prompt through existing Terminal Board commands and the Den skill.
Agent isolation, scheduling, completion detection, retries, and reliable result collection belong to external tools, because owning those provider-specific lifecycle contracts would expand Den into an orchestration runtime.
Keep Notifications general-purpose; agent handoff uses the existing CLI and skill without introducing a Den agent plugin, lifecycle hooks, or agent-specific notification context.
