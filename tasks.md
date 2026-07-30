# SwiftUI 寄せ実装タスク

## 目的

ADR 0007 の SwiftUI-first 方針に従い、SwiftUIで同じ挙動を表現できるAppKit依存を減らす。

AppKitをゼロにすることは目的にしない。
`WKWebView`、global keyboard handling、macOSのシステム連携など、AppKitが必要な境界は維持する。

各タスクは別commitにする。
挙動の変更とbridgeの置換を同じcommitに混ぜない。

## 必読

- `CONTEXT.md`
- `DESIGN.md`
- `docs/testing.md`
- ADR 0006: MVP PoC uses WKWebView
- ADR 0007: Use SwiftUI first with AppKit bridges
- ADR 0020: Test critical UI workflows
- ADR 0027: Support deliberate downloads without managing them

## 実装順

- [ ] S1. Pointer表示を`PointerStyle`へ移す
- [ ] S2. App非アクティブ時の処理を`ScenePhase`へ移す
- [ ] S3. Desk labelの全選択を`TextSelection`へ移す
- [ ] S4. Window外観bridgeをSwiftUIの`WindowStyle`へ移す
- [ ] S5. `WebKit for SwiftUI`との互換性を調査する

### S1. Pointer表示を`PointerStyle`へ移す

対象:

- `Features/Den/Board/BoardView.swift`
- `Features/Den/Board/BoardStrip.swift`
- `Features/Den/DenView.swift`

実装:

- Boardのドラッグハンドルへ`.pointerStyle(isDragging ? .grabActive : .grabIdle)`を設定する。
- Boardのresize handleへ`.pointerStyle(.columnResize)`を設定する。
- Pointer表示のためだけに使っている`onHover`、`onChange`、`NSCursor`呼び出しを削除する。
- ドラッグ終了時とcancel時の`NSCursor.arrow.set()`を削除する。
- `isDragHandleHovered`が不要になれば削除する。
- 各ファイルから未使用の`AppKit` importを削除する。
- Boardの並べ替え、resize、animationは変更しない。

検証:

- `just check`
- `just ui-test Den_BrowserUITests/testOrganizesBoardsUsingPointer`
- 探索確認として、Board headerのhover中はopen hand、ドラッグ中はclosed handになることを確認する。
- 探索確認として、resize handleのhover中は左右resize pointerになることを確認する。
- Window外へドラッグしてcancelした後、Pointerが通常表示へ戻ることを確認する。

受け入れ条件:

- Pointer表示が操作状態に追従する。
- Pointerを通常表示へ戻す命令的な処理が残らない。
- Boardの並べ替えとresizeの挙動が変わらない。

参考:

- <https://developer.apple.com/documentation/swiftui/pointerstyle>

### S2. App非アクティブ時の処理を`ScenePhase`へ移す

対象:

- `Features/Den/DenView.swift`

実装:

- `@Environment(\.scenePhase)`を追加する。
- `NSApplication.didResignActiveNotification`の購読を`scenePhase`の監視へ置き換える。
- phaseが`.active`以外へ変わったとき、進行中のBoard dragとDesk dragをcancelする。
- activeなProfile Windowを切り替えた場合も、操作中のWindowに仮の並び順が残らないことを確認する。
- drag以外のpresentation stateは変更しない。

テスト:

- 必要なら、phase変化からdrag cancelを呼ぶ判断を小さな関数へ抽出してunit testする。
- production codeから`ScenePhase`を模倣する型は追加しない。

検証:

- `just check`
- `just ui-test Den_BrowserUITests/testOrganizesBoardsUsingPointer`
- `just ui-test Den_BrowserUITests/testReordersDesksUsingPointer`
- 探索確認として、ドラッグ中に別アプリへ切り替え、元の順序へ戻ることを確認する。
- 複数のProfile Windowがある状態でも同じ確認を行う。

受け入れ条件:

- Appまたは対象sceneが非アクティブになるとdragがcancelされる。
- `NSApplication.didResignActiveNotification`への依存がなくなる。
- drag以外の操作へ影響しない。

参考:

- <https://developer.apple.com/documentation/swiftui/scenephase>

### S3. Desk labelの全選択を`TextSelection`へ移す

対象:

- `Features/Den/DenView.swift`
- `Features/Den/Desk/DeskPanels.swift`

実装:

- Desk label用の`TextSelection?` stateを、Desk作成panelの一時UI stateとして保持する。
- `TextField`のtext selection bindingへ接続する。
- Desk Preset選択後にlabelを設定し、その文字列全体をselectionへ設定する。
- `NSApp.sendAction`と`NSText.selectAll`を削除する。
- selectionを`DenStore`や永続`DenState`へ移さない。
- `Task.yield()`などの遅延は、同期的なselection更新で動作しない場合に限って追加する。

テスト:

- selection rangeを組み立てる純粋な処理を追加した場合だけunit testする。
- AppKitのfirst responderを使う専用test helperは追加しない。

検証:

- `just check`
- 探索確認として、Desk Presetを選択するとDesk label全体が選択されることを確認する。
- 選択直後の入力で既存labelが置き換わることを確認する。
- IME入力とReturnによる確定が従来どおり動くことを確認する。

受け入れ条件:

- Desk Preset選択後のlabel全選択が維持される。
- `DenView`から`NSApp`と`NSText`への依存がなくなる。
- S1とS2が完了済みなら、`DenView.swift`から`AppKit` importを削除できる。

参考:

- <https://developer.apple.com/documentation/swiftui/textselection>

### S4. Window外観bridgeをSwiftUIの`WindowStyle`へ移す

対象:

- `App/Den_BrowserApp.swift`
- `Features/Profiles/ProfileViews.swift`

実装:

- `WindowGroup`へ`.windowStyle(.hiddenTitleBar)`を設定する。
- `WindowAppearance: NSViewRepresentable`を削除する。
- `ProfileWindowView`の`.background(WindowAppearance())`を削除する。
- `ProfileViews.swift`から未使用になる`AppKit` importを削除する。
- Settings sceneのwindow styleは変更しない。
- 見た目の同等性が成立しない場合、無理に置換せず変更を戻す。

検証:

- `just check`
- 通常表示でcontentがtitlebar領域まで伸びることを確認する。
- Windowのtraffic light、toolbar、Profile chipの位置を確認する。
- Zen Viewへの出入りでtoolbar表示とtop insetが変わらないことを確認する。
- 複数のProfile Windowを開き、各Windowの外観が一致することを確認する。
- Settings Windowのtitlebarが変わらないことを確認する。

受け入れ条件:

- 現在の透明titlebarとfull-size contentの見た目を維持する。
- Zen Viewのtoolbar制御を維持する。
- `WindowAppearance` bridgeがなくなる。

参考:

- <https://developer.apple.com/documentation/swiftui/windowstyle>

### S5. `WebKit for SwiftUI`との互換性を調査する

このタスクではproduction codeを移行しない。
調査結果をADRへ記録し、そのADRを基に移行タスクを改めて分割する。

対象:

- `Features/Den/Board/BoardRuntime.swift`
- `Features/Den/Board/BoardWebView.swift`
- `Features/Den/DrawerView.swift`
- `Features/SheetNavigation/SheetNavigationManager.swift`

確認項目:

- `WKWebsiteDataStore`をProfileごとに共有できるか。
- isolated `WKContentWorld`へ起動scriptとmessage handlerを登録できるか。
- Command click、Command Shift click、Option clickを区別できるか。
- `target=_blank`を新しいBoardへ渡せるか。
- download開始、保存先選択、完了、失敗を現在と同じ粒度で扱えるか。
- JavaScriptのalert、confirm、promptを扱えるか。
- HTML file inputでfileとdirectoryの選択条件を扱えるか。
- element fullscreenとnative Picture in Pictureを扱えるか。
- page zoom、back-forward navigation、reloadを扱えるか。
- Board focus時とDrawer Preview表示時にfirst responderを制御できるか。
- live runtimeを永続`DenState`から分離したまま、`WebPage`を一つの`WebView`へ保持できるか。
- 現在のSheet Navigation testとUI testを同じ意図で維持できるか。

成果物:

- `docs/adr/`へ採用または見送りのADRを追加する。
- 採用する場合、runtime model、navigation、Sheet Navigation、downloadとdialog、focus bridgeを別タスクに分ける。
- 見送る場合、不足しているAPIと再評価条件をADRへ記録する。

受け入れ条件:

- 現行機能との対応表がADRにある。
- 未確認項目を「対応可能」と断定しない。
- 調査中のadapterやsample codeがproduction targetへ残らない。

参考:

- <https://developer.apple.com/documentation/webkit/webkit-for-swiftui>
- <https://developer.apple.com/documentation/webkit/building-a-cross-platform-web-browser>

## 今回は移行しないAppKit境界

以下は、SwiftUIへ寄せることでコードが単純になる根拠がないため対象外とする。

- `KeyboardController`のapp-wide `NSEvent` monitor。
- IMEのmarked textとfirst responderの判定。
- Shortcut recording中の生key event取得とmacOS menu shortcutの競合判定。
- default browser設定に使う`NSWorkspace`。
- Sheet Navigationからのprogrammatic clipboard操作。
- download destinationとHTML file inputに使うsave panelとopen panel。
- `WKUIDelegate`から同期的に応答するJavaScript dialog。
- Settings Windowを含む現在のWindowを閉じる`NSApp`操作。

これらはS5で`WebKit for SwiftUI`への移行を採用した場合、影響する境界だけを再評価する。
