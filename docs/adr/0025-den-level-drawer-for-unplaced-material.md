---
status: accepted
---

# Add a Den-level Drawer for material without a settled work context

Den Browser provides a Profile-isolated, Den-wide Drawer for web material whose Desk or Board context is unsettled, so external links need not disrupt an established Desk layout or require a temporary Desk.
Drawer Items are independent of live Sheets and remain available across Desk changes; they carry no implicit unread or actionable status, and placement can continue an existing Peek without reloading it.
The Drawer starts with web material rather than a speculative generic content model; current behavior is documented in [Drawer Controls](../shortcuts.md#drawer-controls), with [runtime ownership](../architecture.md#den-state-and-live-runtimes) separate from [persisted state](../persistence.md).
