# Project Tasks

<!-- Status: [ ] open / [/] in progress / [x] complete / [-] cancelled. -->

## Contents

- [/] [TASK-001：アクセシブルな名前と状態を整える](#task-001アクセシブルな名前と状態を整える)
- [x] [TASK-002：ポインター専用操作に代替手段を追加する](#task-002ポインター専用操作に代替手段を追加する)
- [TASK-003：大きい文字とコントラストに耐える](#task-003大きい文字とコントラストに耐える)
- [TASK-004：macOS実機と回帰検証を行う](#task-004macos実機と回帰検証を行う)

## Current Status

TASK-001のコード対応を完了。VoiceOver手動確認は任意とし、TASK-002のコード対応とComputer Use検証を完了した。
監査で見つかった不足を、意味・操作・表示・検証の4 taskに分けて追跡する。

## Tasks

### [/] TASK-001：アクセシブルな名前と状態を整える

#### Purpose

VoiceOverが操作対象の意味、現在の選択状態、Boardの補足情報を読み上げられるようにする。

#### Prerequisites

- なし

#### Work

- [x] Picture in PictureとVim-style Sheet NavigationのToggleに明示的なアクセシブルな名前を付ける。
- [x] Desk switcherのPresented Deskを選択状態として公開する。
- [x] Overviewの選択中DeskとBoardを選択状態として公開する。
- [x] Overview Boardのラベルに、必要なURL・Terminal・Zellij・zmxの補足情報を含める。
- [ ] パネル表示時のアクセシビリティフォーカスと、装飾用アイコンの読み上げを確認する。

#### Acceptance Criteria

- [/] VoiceOverが各Toggleを用途付きで識別できる。
- [/] Desk switcherとOverviewで、現在選択中の項目が状態として読み上げられる。
- [/] 同名のBoardをOverviewで補足情報により区別できる。
- [ ] Den、Desk、Board、Sheet、Drawerの用語を維持する。

#### Verification

コード対応済み。`just check`、Overview/Deskの既存ポインターUIテストは成功。
VoiceOver手動確認は実施せず、Den全体のComputer Use検証はTASK-004で扱う。

### [x] TASK-002：ポインター専用操作に代替手段を追加する

#### Purpose

ドラッグできない利用者もDesk・Boardの整理とBoard幅変更を完了できるようにする。

#### Prerequisites

- なし

#### Work

- [x] Desk reorderにキーボードまたはVoiceOverの左右移動アクションを追加する。
- [x] BoardResizeHandleを調整可能なアクセシビリティ要素として公開する。
- [x] Overview Boardの移動をVoiceOverアクションまたは同等の操作として公開する。
- [x] 既存のポインター操作、Den ModeのBoard移動、Overviewのキーボード操作を維持する。

#### Acceptance Criteria

- [x] ポインターなしでDeskの並べ替えを完了できる。
- [x] ポインターなしでFocused Desk内のBoard移動とBoard幅変更を完了できる。
- [x] ポインターなしでOverviewのBoard移動を完了できる。
- [x] 範囲外キャンセル、Desk切替、Focus状態、既存のドラッグ挙動が変わらない。

#### Verification

2026-08-16、`/Users/hiroaki/projects/niri-browser/.derived-data/Build/Products/Debug/Den Browser.app`をComputer Useで操作した。
アクセシビリティツリーからDesk・Board・Overview Boardの移動アクションとBoard幅のIncrement/Decrementを取得し、以下を実行した。
Desk左右移動、Focused Desk内Board左右移動、Board幅656→736→656ポイント、Overview内Board左右移動、OverviewのDesk間移動を確認した。
各操作後にAXツリーで順序・選択状態・幅を確認し、すべて元の状態へ復元した。`just check`と既存のDesk・Focused Desk・OverviewのポインターUIテストも成功。
VoiceOver手動確認は、このComputer Use検証の代替として実施しない。

### TASK-003：大きい文字とコントラストに耐える

#### Purpose

固定レイアウトと低コントラストの視覚設計が、文字拡大やコントラスト強調時の情報欠落を起こさないようにする。

#### Prerequisites

- TASK-001：状態表示の意味を確定する

#### Work

- [ ] Settings、Denパネル、Keyboard Shortcuts、Overviewの固定幅・固定高を大きい文字で確認する。
- [ ] Desk名、Drawer項目、Boardヘッダー、Overviewカードの切れ・重なり・過度な省略を解消する。
- [ ] Desk・Board・Overviewの選択表示、無効状態、検索欄の境界線をコントラスト強調設定で確認・調整する。
- [ ] 色以外の状態表現と既存のReduce Motion対応を維持する。

#### Acceptance Criteria

- [ ] macOSの大きい文字設定で、主要な操作名・状態・入力内容が欠落しない。
- [ ] コントラスト強調設定で、主要なテキスト、操作境界、選択状態を識別できる。
- [ ] 選択状態が色だけに依存しない。
- [ ] 通常表示のレイアウトとSheetの表示領域を不必要に壊さない。

#### Verification

未実施。大きい文字、コントラスト強調、通常表示、Reduce Motionの組み合わせを実機で確認する。

### TASK-004：macOS実機と回帰検証を行う

#### Purpose

SwiftUI、WKWebView、Ghosttyの境界を含むアクセシビリティ対応を実際のmacOS環境で確認し、再発を防ぐ。

#### Prerequisites

- TASK-001：アクセシブルな名前と状態を整える
- TASK-002：ポインター専用操作に代替手段を追加する
- TASK-003：大きい文字とコントラストに耐える

#### Work

- [ ] Computer UseでDen、Desk、Board、Overview、Drawer、Settingsを通しで操作する。
- [ ] Terminal BoardのGhostty側アクセシビリティ公開範囲を確認する。
- [ ] WKWebViewのSheet入力、Drawer Preview入力、ネイティブダイアログのフォーカス移動を確認する。
- [ ] 安定した状態・ラベル・操作をXCUITestまたはfocused unit testでカバーする。
- [ ] `docs/testing.md`のアクセシビリティ検証方針を必要に応じて更新する。

#### Acceptance Criteria

- [ ] Computer Useで主要なDen操作を完了できる。
- [ ] Terminal Board、Sheet、Drawer Previewからの入力フォーカスが破綻しない。
- [ ] `just check`と関連UIテストが成功する。
- [ ] 実機確認結果と未対応の外部依存が記録されている。

#### Verification

TASK-002でDesk・Board・OverviewのComputer Use検証を実施済み。
Drawer・Settings・Ghostty・WKWebViewを含む通しのComputer Use検証、`just check`、関連UIテストの記録は未実施。

## Common Acceptance Criteria

- [ ] macOS 26.0を最低対応バージョンとし、不要な古いOS向け分岐を追加しない。
- [ ] DenStateとBoardRuntime・WKWebView・Terminalの責務境界を維持する。
- [ ] アクセシビリティ対応のためだけに新しい依存関係、Coordinator、Service、抽象protocolを追加しない。
- [ ] 既存のキーボード優先設計とポインター操作を維持する。
- [ ] 変更したSwift sourceには`just check`を実行する。

## Deferred Items

- [ ] Ghostty外部パッケージ自体の変更は、TASK-004で不足が確認された場合だけ判断する。
- [ ] WKWebViewが表示する第三者Sheetのアクセシビリティ品質は、Den Browser側の対応範囲と分けて記録する。

## Out of Scope

- 今回のtask登録だけで実装・テスト・commitは行わない。
- Den Browser全体のビジュアルデザイン刷新は行わない。
- 第三者WebサイトのHTMLやアクセシビリティは変更しない。
