# Separate Views from native Runtime ownership

Keep Feature Views and native display attachment in `DenViews`, depending on `DenModels` and `DenDomain`, while App retains WebKit/Ghostty execution, private headers and Runtime ownership.
A single UI-independent Model module keeps Model tests free of display SDKs without forcing native execution behind another Model layer.
App supplies existing `NSView` instances and callbacks so display composition preserves native resource identity and lifetime.
