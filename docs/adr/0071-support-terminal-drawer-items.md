---
status: accepted
---

# Support Terminal Drawer Items with stable placement identity

Drawer Items hold Web material or Terminal session configuration in the version 4 Profile format, reusing the existing Shell, Zellij and zmx session model. Terminal Items keep their Profile-owned runtime across Peek changes and transfer it to a Board without restarting; their Item UUID reserves the eventual Board ID so the Shell's `DEN_BOARD_ID` remains useful after placement without rewriting process environments. Before placement that ID does not identify a Board, so Board-targeted CLI operations fail while Desk and Drawer operations retain Profile targeting.

Web and Terminal Primary Boards without a Side Board can move into Drawer without ending their runtime or entering Board removal history. Placement preserves the Item UUID as the Board ID in both directions; Boards with a Side Board remain outside this transfer contract.
