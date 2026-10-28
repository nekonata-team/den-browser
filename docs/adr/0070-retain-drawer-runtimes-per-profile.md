---
status: accepted
---

# Retain opened Drawer runtimes per Profile

An opened Drawer Item retains one Profile-owned runtime across Peek collapse, Item switches and window closure while another Profile window remains, preserving forms and live work. Opening the same Item in another window moves its presentation and input ownership there; placement transfers that runtime to a Board even when its Peek is collapsed. This spends resources on previously opened Items in exchange for continuity; unopened Items remain lazy, and discard or final Profile-window teardown releases their runtimes. Drawer remains a temporary presentation rather than a concurrent work surface, as defined in ADR 0030.
