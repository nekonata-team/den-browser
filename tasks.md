# Project Tasks

<!-- Status: [ ] open / [/] in progress / [x] complete / [-] cancelled. -->

## Contents

- [/] [TASK-001：アクセシブルな名前と状態を整える](#task-001アクセシブルな名前と状態を整える)
- [x] [TASK-002：ポインター専用操作に代替手段を追加する](#task-002ポインター専用操作に代替手段を追加する)
- [x] [TASK-003：色に依存しない選択状態を示す](#task-003色に依存しない選択状態を示す)
- [TASK-004：macOS実機と回帰検証を行う](#task-004macos実機と回帰検証を行う)

## Current Status

TASK-001のコード対応を完了。VoiceOver手動確認は任意とし、TASK-002のコード対応とComputer Use検証を完了した。TASK-003はmacOSのテキストサイズ対応を対象外とし、色以外で区別する選択表示と境界線の対応を完了した。
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

### [x] TASK-003：色に依存しない選択状態を示す

#### Purpose

選択状態と操作中の境界線が色だけに依存しないようにする。

#### Prerequisites

- TASK-001：状態表示の意味を確定する

#### Work

- [x] Board、Terminal Board、Overview、Desk、Drawerの選択表示と検索欄の境界線を、`accessibilityDifferentiateWithoutColor` が有効な場合に主色の輪郭でも示す。
- [x] 色以外の選択状態（アクセシビリティの選択状態、輪郭）と既存のReduce Motion対応を維持する。

#### Acceptance Criteria

- [x] `カラー以外で区別` を有効にすると、主要な操作境界と選択状態を識別できる。
- [x] 選択状態が色だけに依存しない。
- [x] 通常表示のレイアウトを変更しない。

#### Verification

macOSの「カラー以外で区別」を有効化し、Computer UseでBoardの選択枠、Overviewの選択Board、Drawerの検索欄の境界線をスクリーンショットで確認した。確認後に設定をオフへ戻し、Den Browserの画面も復元した。
`just check`とBoard/Overview/DeskのポインターUIテストは成功。macOSのテキストサイズ変更は対象外とした。

### TASK-004：macOS実機と回帰検証を行う

#### Purpose

SwiftUI、WKWebView、Ghosttyの境界を含むアクセシビリティ対応を実際のmacOS環境で確認し、再発を防ぐ。

#### Prerequisites

- TASK-001：アクセシブルな名前と状態を整える
- TASK-002：ポインター専用操作に代替手段を追加する
- TASK-003：色に依存しない選択状態を示す

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

TASK-002でDesk・Board・Overviewの操作、TASK-003でOverview・Drawerの通常表示とコントラスト設定のComputer Use検証を実施済み。
Settings・Ghostty・WKWebViewを含む通しのComputer Use検証は未実施。

## Common Acceptance Criteria

- [ ] macOS 26.0を最低対応バージョンとし、不要な古いOS向け分岐を追加しない。
- [ ] DenStateとBoardRuntime・WKWebView・Terminalの責務境界を維持する。
- [ ] アクセシビリティ対応のためだけに新しい依存関係、Coordinator、Service、抽象protocolを追加しない。
- [ ] 既存のキーボード優先設計とポインター操作を維持する。
- [ ] 変更したSwift sourceには`just check`を実行する。

## Deferred Items

- [ ] Ghostty外部パッケージ自体の変更は、TASK-004で不足が確認された場合だけ判断する。
- [ ] WKWebViewが表示する第三者Sheetのアクセシビリティ品質は、Den Browser側の対応範囲と分けて記録する。
- [ ] macOSの「テキストサイズ」に連動するDen Browser全体の文字サイズ変更は、対応方針と実装方法を決めるまで保留する。

## Out of Scope

- 今回のtask登録だけで実装・テスト・commitは行わない。
- Den Browser全体のビジュアルデザイン刷新は行わない。
- 第三者WebサイトのHTMLやアクセシビリティは変更しない。
