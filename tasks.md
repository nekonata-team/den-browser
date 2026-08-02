# Code smell 改善タスク

## 目的

挙動を変えず、次の具体的な smell を減らす。

- `DenView` が子Viewの一時状態と操作詳細まで所有している。
- BoardとDeskの水平ドラッグ計算が重複している。
- `NewDeskPanel` と `BoardRuntime` の引数が多く、責務境界が読み取りにくい。

ファイル行数だけを理由に分割しない。
単一実装のprotocol、Repository、Coordinator、Service、基底runtimeは追加しない。
抽出後のproduction codeが増えるだけなら、その抽出は行わない。

各タスクは別commitにする。
機能変更を混ぜない。

## 必読

- `CONTEXT.md`
- `docs/architecture.md`
- `docs/testing.md`
- ADR 0007: Use SwiftUI first with AppKit bridges
- ADR 0020: Test critical UI workflows
- ADR 0028: Defer WebKit for SwiftUI migration

## 実装順

- [x] C1. BoardとDeskの水平ドラッグ計算を共通化する
- [x] C2. New Desk系panelの一時状態を`NewDeskPanel`へ移す
- [x] C3. Desk切替と並べ替えを`DeskSwitcher`へ集約する
- [x] C4. Board表示と並べ替えを`BoardStrip`へ集約する
- [x] C5. `BoardRuntime`のaction配線を整理する

### C1. BoardとDeskの水平ドラッグ計算を共通化する

根拠:

- `BoardDragInsertion.targetIndex`と`DeskDragInsertion.targetIndex`は名前以外が同じ。
- BoardとDeskのedge auto-scrollも、対象配列とedge幅以外は同じ。
- lifecycleまで共通化すると、store操作と復元条件の違いが隠れる。

実装:

- 2つのinsertion型を、IDに依存しないfeature-localな純粋関数へ統合する。
- edge auto-scrollは、方向、隣接ID、実行間隔を決める純粋計算だけを共有する。
- drag state、開始、終了、cancel、store更新はBoardとDeskに残す。
- 汎用drag frameworkやprotocolは追加しない。

テスト:

- 重複しているinsertion testを1組へ統合する。
- 左右の境界、隣接要素の中心を越える条件、geometry不足を検証する。
- edge内外、先頭と末尾、速い再実行と遅い再実行を検証する。

受け入れ条件:

- BoardとDeskが同じ水平判定を使う。
- 並べ替え開始、preview、範囲外drop時の復元は変わらない。
- production codeの行数が減る。

検証:

- `just check`
- `just ui-test Den_BrowserUITests/testOrganizesBoardsUsingPointer`
- `just ui-test Den_BrowserUITests/testReordersDesksUsingPointer`

### C2. New Desk系panelの一時状態を`NewDeskPanel`へ移す

根拠:

- `NewDeskPanel`は19個のbinding、値、callbackを受け取る。
- preset選択、検索、label、validation、focusの状態はpanel内だけで使う。
- 現在はその状態と操作が`DenView`へ逆流し、親Viewの変更理由を増やしている。

実装:

- preset選択、検索、管理表示、label、selection、validation、focusを`NewDeskPanel`が所有する。
- preset確定、Desk作成・置換、削除後のfallbackもpanel側へ移す。
- `DenView`はpanelの表示位置と`temporaryContext`による選択だけを担当する。
- 状態をまとめるだけの参照型やViewModelは作らない。SwiftUIのlocal stateで足りる限り使う。
- `.newDesk`、`.replaceDesk`、`.deskPresetManagement`の切替時に初期状態を明示する。

テスト:

- `DenStoreDeskPresetTests`で作成、置換、削除のdomain挙動を維持する。
- 純粋なfallback判定を抽出した場合だけfocused unit testを追加する。

受け入れ条件:

- `DenView`からNew Desk系panel専用の`@State`と`@FocusState`がなくなる。
- `NewDeskPanel`のinitializerが、内部状態をbindingで受け取らない。
- preset削除、Replace Desk、IME確定、Escape/Shift-Tabの挙動が変わらない。

検証:

- `just check`
- New Desk、Replace Desk、Manage Presetsを探索確認する。
- Personal Desk Preset削除時、選択とlabelが有効なfallbackへ戻ることを確認する。

### C3. Desk切替と並べ替えを`DeskSwitcher`へ集約する

根拠:

- `DeskSwitcher`は37行の汎用shellだが、呼び出し元は1つだけ。
- `AnyView`化したitem closureとframe callbackを通し、実処理は`DenView`にある。
- Desk button、context menu、frame、scroll、dragは1つのUI責務である。

実装:

- Desk item、context menu、frame収集、scroll position、drag stateを`DeskSwitcher`へ移す。
- `item: (...) -> AnyView`と`onFramesChange`を削除し、concreteなfeature Viewにする。
- drag cancellation request、`temporaryContext`、focused Desk変更、Window非アクティブを`DeskSwitcher`内で処理する。
- `DenView`には表示条件、配置、Profile色だけを残す。
- Desk専用controllerやreorder serviceは追加しない。

テスト:

- C1の純粋関数testを維持する。
- 必要ならcancel条件だけを純粋関数として追加検証する。

受け入れ条件:

- `DenView`からDesk drag、frame、scroll、auto-scroll stateと関連methodがなくなる。
- `DeskSwitcher`に`AnyView`とitem builderがない。
- click、context menu、並べ替え、範囲外drop、非アクティブ時cancelが変わらない。

検証:

- `just check`
- `just ui-test Den_BrowserUITests/testReordersDesksUsingPointer`
- Window外drop、別アプリ切替、panel表示中のcancelを探索確認する。

### C4. Board表示と並べ替えを`BoardStrip`へ集約する

根拠:

- `BoardStrip`自身がScrollViewとBoard群を描画する一方、scroll、frame、drag、resize、centering stateは`DenView`が持つ。
- その分割により、`BoardStrip`は多数のbindingとcallbackを必要としている。
- Board Strip内だけで完結する表示操作を親へ戻す理由がない。

実装:

- Board frame、scroll position、drag、resize、centering待機を`BoardStrip`へ移す。
- alignment変更、focused Board center request、Desk filter選択scrollを`BoardStrip`内で処理する。
- drag cancellation request、focused Desk変更、`temporaryContext`、Window非アクティブを`BoardStrip`内で処理する。
- Open Board panelを開くactionなど、親との境界を越えるcallbackだけ残す。
- layout計算の純粋関数は`BoardLayout`に維持する。
- Board専用controllerやscroll serviceは追加しない。

テスト:

- `BoardLayoutTests`とC1の純粋関数testを維持する。
- centering条件を新たに純粋化した場合だけfocused unit testを追加する。

受け入れ条件:

- `DenView`からBoard drag、frame、scroll、resize、centering stateと関連methodがなくなる。
- `BoardStrip`のinitializerには、内部イベントを親へ中継するcallbackが残らない。
- pointer focus、resize、並べ替え、filter、Desk切替後の位置、Board追加animationが変わらない。

検証:

- `just check`
- `just ui-test Den_BrowserUITests/testOrganizesBoardsUsingPointer`
- `just ui-test Den_BrowserUITests/testNewBoardAnimatesIntoBoardStrip`
- `just ui-test Den_BrowserUITests/testRemovingFocusedBoardSettlesAtLeadingEdge`
- centering設定の各値、Zen View、Desk filterを探索確認する。

### C5. `BoardRuntime`のaction配線を整理する

根拠:

- initializerが多数のclosureを受け、12個をpropertyへ保持する。
- Sheet Navigation用actionを個別に受けた直後、`SheetNavigationManager.Actions`へ詰め直している。
- default no-op closureにより、productionの必須配線漏れを見落としやすい。

実装:

- Sheet Navigation command群を1つの明示的なaction valueとして渡す。
- navigation policy、状態変更、fullscreen、downloadなどruntime自身が使うeventも用途別にまとめる。
- production call siteでは必要なactionを明示する。
- test専用のno-op fixtureは許容するが、production initializerのdefault no-opはなくす。
- actionを実行する新しいCoordinator、delegate wrapper、protocolは追加しない。

テスト:

- `SheetNavigationTests`と`BoardRuntimeWebUITests`を新しいaction valueへ更新する。
- Command-click、targetなしpopup、download完了・失敗、remove/restore commandの既存検証を維持する。

受け入れ条件:

- `BoardRuntime` initializerに長いclosure列がない。
- Sheet Navigation actionの詰め替えが1か所だけになる。
- action配線漏れをdefault no-opが隠さない。
- production codeが増えない。

検証:

- `just check`

## 現時点で追跡しない項目

- `DenStore`の分割: persisted stateとlive runtimeの境界は明確。安定した独立state machineが現れるまで分割しない。
- `SheetNavigationManager`の分割: settings、WebView登録、JS message routingは現在1つのWebKit境界としてまとまっている。Profile別設定や別consumerが必要になった時に再検討する。
- `BoardRuntime`と`DrawerPreviewRuntime`の基底class/factory化: runtimeは2種類だけで、delegate責務も異なる。3つ目の同種runtimeか共通不具合が出るまで共有しない。
- `KeyboardController`と`ProfileManager`の行数分割: 大きいが責務は凝集している。具体的な変更衝突が出るまで分割しない。
- WebKit for SwiftUI移行: ADR 0028の再評価条件が満たされるまで追跡しない。

## 完了の定義

- 各タスクの受け入れ条件を満たす。
- Swift source変更ごとに`just check`が成功する。
- UI test失敗時は変更前でも再現するか確認し、既知失敗として曖昧に処理しない。
- `docs/architecture.md`と責務境界が変わる場合、同じcommitで更新する。
- 終了したタスクはcommit履歴で追えるため、`tasks.md`へ完了詳細を残し続けない。
