---
status: accepted
---

# Confirm deleting desks that contain boards

An empty focused desk is deleted immediately. Deleting a focused desk that contains Boards requires confirmation describing that its Boards and Sheet Stacks will be permanently deleted. The last Desk and the source Desk of a Held Board remain protected from deletion.

This replaces ADR 0009's restriction that only empty Desks can be deleted. Requiring users to close every Board separately made intentional Desk cleanup unnecessarily laborious; confirmation preserves protection against accidental multi-Board data loss.
