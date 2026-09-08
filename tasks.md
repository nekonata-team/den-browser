# Project Tasks

<!-- Status: [ ] open / [/] in progress / [x] complete / [-] cancelled. -->

## Contents

- [x] [TASK-010：リンク操作の移動抑制を操作内で完結させる](#task-010リンク操作の移動抑制を操作内で完結させる)
- [x] [TASK-011：最新の配置要求を優先し遅延処理を失効させる](#task-011最新の配置要求を優先し遅延処理を失効させる)
- [ ] [TASK-012：移動途中のFocus再指定を調査し原因確定後に修正する](#task-012移動途中のfocus再指定を調査し原因確定後に修正する)
- [ ] [TASK-013：Desk切替をまたぐスクロール位置保存を調査する](#task-013desk切替をまたぐスクロール位置保存を調査する)

## Current Status

2026-09-07のアニメーション調査を、別の実装エージェントへ引き継ぐための台帳。
アプリコードは未変更。ユーザー承認により旧タスク本文を置き換えた。
TASK-001〜TASK-009は再利用しない。旧内容はGit履歴（直近の台帳更新は `e68c011`）を参照する。

調査場所は `/Users/hiroaki/projects/niri-browser`。
実装開始時にブランチ、worktree、未コミット変更、対象コードの現状を再確認する。

- TASK-010：実装・unit test・自己レビュー・人間確認完了。Acceptance確認済み。
- TASK-011：実装・unit test・自己レビュー・人間確認完了。保存位置復元中の明示中央配置、要求の識別・失効、Desk／Board／View変更時の取消を反映。Acceptance確認済み。
- TASK-013：競合の候補。再現または因果関係を確認する前に修正しない。
- 調査時の基準結果：`just test` は362件成功。
- `just ui-test Den_BrowserUITests/testDirectDeskSwitchAndDenModeFocusCycle` は1件成功。Desk往復後のSheet Inputを検証する既存テストであり、移動途中の表示や今回の競合を保証するものではない。
- 上記は変更前の結果。各タスクの完了検証として流用しない。

## Purpose and Goals

BoardのFocus移動、Desk移動、リンクからのBoard作成で、選択状態と表示位置の意図しない食い違いを防ぐ。
最初に直す対象はアニメーション時間・曲線ではなく、配置要求の優先順位、適用条件、失効条件とする。

- 新しい明示操作が、古い自動配置・復元要求によって捨てられない。
- リンク操作の移動抑制が、無関係な後続操作へ残らない。
- 旧Deskのスクロール・遅延処理が新Deskに作用しない。
- 連続入力で待機中または進行中の移動先を更新できる。
- `Always`、`When Overflowing`、`Never`、Reduced Motionの既存方針を維持する。

実装前に [CONTEXT.md](CONTEXT.md)、[DESIGN.md](DESIGN.md)、[architecture.md](docs/architecture.md)、[testing.md](docs/testing.md)、
[ADR 0029](docs/adr/0029-keep-boards-spatially-visible.md)、[ADR 0037](docs/adr/0037-present-distinct-desks-in-profile-windows.md)、
[ADR 0046](docs/adr/0046-activate-boards-on-viewport-visibility.md) を読む。
キーボード経路を変更する場合は [keyboard-input.md](docs/keyboard-input.md) も読む。

## Tasks

### [x] TASK-010：リンク操作の移動抑制を操作内で完結させる

#### Purpose

リンク元へのクリックFocusを抑制する状態が、新規Boardの配置や次のDesk切替まで抑制する不備を解消する。

#### Prerequisites

- なし。呼び出し元とイベント順序を確認し、意味のある最小の失敗検証を用意する。

#### Evidence and Entry Points

- [BaseWebRuntime.swift](<Den Browser/Den Browser/Features/Den/BaseWebRuntime.swift>) の `decidePolicyFor` は、リンク処理の前に `handleLinkActivation` を呼ぶ。
- [DenStore+Runtime.swift](<Den Browser/Den Browser/Features/Den/Store/DenStore+Runtime.swift>) の `onLinkActivated` は、リンク元Board IDで `prepareBoardLinkFocus` を呼ぶ。
- [BoardRuntime.swift](<Den Browser/Den Browser/Features/Den/Board/BoardRuntime.swift>) の `openBoardFromModifierClick` は、Shift付きなら新規BoardをFocusする。targetless navigationにも新規Board作成経路がある。
- [BoardStrip.swift](<Den Browser/Den Browser/Features/Den/Board/BoardStrip.swift>) の `onChange(of: alignmentTarget)` は、Focus先がリンク元と一致した場合だけ消費を予約する。不一致かつ `layoutChanged` なら、抑制状態を残してreturnする。
- リンク元Aへの印と新規Board BへのFocusが同じ描画更新にまとまると、この不一致経路へ入る。その後のDesk変更も同じ条件で早期終了し得る。

#### Work

- [x] Webの通常クリック、Cmd-click、Cmd-Shift-click、targetless navigation、Terminalリンク、Sheet Navigation経由の呼び出しを追い、印の設定・消費・取消の範囲を確定する。
- [x] 抑制をリンク元へのクリックFocusに限定する。明示的なFocus変更、Desk変更、対象Board削除、処理完了後へ残さない。
- [x] 新規BoardをFocusする経路には、そのBoardに対する通常の配置方針を適用する。背景作成は既存のFocusと表示位置を維持する。
- [x] `consumeBoardLinkFocus` の古い通知が新しい印を消さない契約を維持する。印を追加するだけの局所対処を各呼び出し元へ重複させない。
- [x] [shortcuts.md](docs/shortcuts.md) の既存記述で「リンククリック時の自動センタリング抑制」と新規Board操作の関係を確認した。追加変更なし。

#### Acceptance Criteria

- [x] リンク元AからBを作成してFocusした後、後続のFocus・Desk移動・配置変更が古いリンク抑制に妨げられない。
- [x] 同一Board内のリンククリックや背景Board作成で、不必要な中央配置が発生しない。
- [x] 連続するリンク操作で、古い消費通知が最新操作の状態を消さない。

#### Verification

2026-09-07実施。
- `just check` 成功。swift-format、swiftlint、unit test 364件成功。
- 回帰テストで「Foreground Board作成は抑制を残さない」「Background Board作成の抑制は次のFocusで失効する」「古いconsume通知は新しい印を消さない」を確認。
- WebKit固有の実機連続操作（通常クリック、Cmd-click、Cmd-Shift-click、targetless navigation、Terminalリンク、Sheet Navigation）は、今回の人間確認では追加再現なし。問題が再発した場合は新規起票する。

---

### [x] TASK-011：最新の配置要求を優先し遅延処理を失効させる

#### Purpose

位置復元中に新しい中央配置要求を捨てる不備を直し、配置処理の受付・置換・適用条件を追跡可能にする。

#### Prerequisites

- TASK-010完了。リンク抑制の修正を前提に、同じBoardStrip内の配置処理を整理する。

#### Evidence and Entry Points

- [BoardStrip.swift](<Den Browser/Den Browser/Features/Den/Board/BoardStrip.swift>) の `centerFocusedBoardRequest` observerは、待機要求が `.resting` なら無条件にreturnする。
- Desk切替時の保存位置復元も、非overflow時の自動整列も `.resting` を使う。
- [DenStore+BoardOperations.swift](<Den Browser/Den Browser/Features/Den/Store/DenStore+BoardOperations.swift>) の `centerFocusedBoard()` は保存位置を消すため、新要求が捨てられるとStoreと表示が食い違う。
- `centerBoard`、`revealBoard`、`deferBoardAlignment`、`settlePendingBoardAlignment` で要求の設定・取消が分散している。後者はTaskのyield前に条件を検証し、yield後は取消状態とpendingの有無だけを確認している。

#### Work

- [x] 明示的な中央配置と自動配置・復元の発生元を確認し、同じ更新内の自動要求と後から来た明示操作を区別する。
- [x] 後から来た明示操作で待機中の復元要求を置き換える。一律の `.resting` 優先を解消する。
- [x] BoardStrip内の既存 `PendingBoardAlignment` を活用し、受付・置換・取消・適用の重複を必要な範囲で集約する。
- [x] 遅延処理の適用直前に、要求の識別、対象Desk、対象Boardの存続、必要なレイアウト条件を検証する。古い要求が新しいpendingを消さないようにする。
- [x] Desk変更、空Desk、対象Board削除、View破棄時の失効を確認する。固定sleepや待機Taskを追加して順序問題を隠さない。
- [x] [BoardLayout.swift](<Den Browser/Den Browser/Features/Den/Board/BoardLayout.swift>) の純粋な座標計算と [DenMotion.swift](<Den Browser/Den Browser/Features/Den/Design/DenMotion.swift>) を再利用する。要求ID等は必要な最小構成とし、汎用アニメーション管理層を作らない。

#### Acceptance Criteria

- [x] 保存位置の復元待ちに中央配置を要求すると、最新要求が適用される。
- [x] 自動配置・復元は、新しい明示操作がない場合に従来どおり機能する。
- [x] 旧要求の遅延完了が、新しい要求・別Desk・削除済みBoardへ作用しない。
- [x] レイアウト待ちを維持しつつ、連続入力をアニメーション完了まで待たせない。

#### Verification

2026-09-09：`just check` 成功（format、lint、Den BrowserTests）。追加した `BoardAlignmentTests` で、古い要求の完了が新しいpendingを有効扱いしないこと、対象Desk／Board不一致を無効とすることを検証。
実時間sleepは追加せず、要求ID・Desk・Board・layoutKeyを適用直前に再検証。Desk変更、空Desk、Board削除、View破棄は共通取消経路へ接続した。
最大化、Board幅変更、Desk Filter確定は既存のlayoutKey検証経路を再利用。人間確認でAcceptance Criteriaを確認済み。

---

### [ ] TASK-012：移動途中のFocus再指定を調査し原因確定後に修正する

#### Purpose

移動途中でFocusを戻した際、前の移動が続いて選択と表示位置が離れる候補を確認する。

#### Prerequisites

- TASK-011完了。待機要求の競合と、開始済みスクロールの再指定を分けて調べる。

#### Evidence and Entry Points

[BoardStrip.swift](<Den Browser/Den Browser/Features/Den/Board/BoardStrip.swift>) の `revealBoard` は、
現在の座標で対象が可視ならpendingとTaskを取り消してreturnする。
この分岐には、開始済み `ScrollPosition` アニメーションを停止・再指定する処理がない。
SwiftUIがこの場合に実際にどう動くかは未確認であり、現時点では不具合と断定しない。

#### Work

- [ ] `Never`／`When Overflowing` で、画面外Boardへの移動途中に画面内BoardへFocusを戻す。比較として `Always` とReduced Motionも確認する。
- [ ] Focus ID、現在位置、要求した移動先、scroll phaseの順序を必要な範囲で観測する。単発操作の最終座標だけで判定しない。
- [ ] 原因が確認できた場合のみ、現在位置に加えて進行中の移動先を考慮し、最新操作に合わせて停止・再指定する。
- [ ] 未再現または正常動作なら、その条件と結果を記録し、推測の修正を入れない。根拠が足りなければDeferred Itemsへ移す。

#### Acceptance Criteria

- [ ] 再現結果と因果関係、または修正不要と判断した根拠が記録されている。
- [ ] 修正する場合、最新Focusへの可視性・中央配置方針を満たし、古い移動先へ進み続けない。
- [ ] 連続入力、逆方向への入力、ユーザーの直接スクロールを不必要に妨げない。

#### Verification

未実施。判断ロジックはunit test、進行中スクロールの視覚的挙動は探索確認で検証する。
XCUITestを追加する場合は、保護するnative境界とunit testでは観測できない失敗を事前に記録する。
単なるボタンクリックや見た目だけを理由に追加しない。

---

### [ ] TASK-013：Desk切替をまたぐスクロール位置保存を調査する

#### Purpose

旧Deskで始めたスクロールの終了通知が、新Deskの保存位置を上書きする候補を確認する。

#### Prerequisites

- TASK-011完了。配置要求のDesk所有と失効条件を前提に、スクロール操作の所有を確認する。

#### Evidence and Entry Points

[BoardStrip.swift](<Den Browser/Den Browser/Features/Den/Board/BoardStrip.swift>) の `onScrollPhaseChange` は、
操作開始時のDeskを保持せず、終了時の `store.presentedDeskID` に `scrollGeometry.offsetX` を保存する。
同じScrollViewを使ったDesk切替で、慣性スクロールの終了通知がどの順序になるかは未確認。

#### Work

- [ ] 異なる保存位置を持つDeskを用意し、直接操作・慣性スクロール中にDeskを切り替える。旧Deskと新Desk両方の保存値・復元位置を確認する。
- [ ] 再現した場合は、操作開始時のDeskに所有を結び付け、Desk切替後の古い終了通知を破棄する。
- [ ] 保存時の座標には、必要に応じて通知時点の [ScrollPhaseChangeContext.geometry](https://developer.apple.com/documentation/swiftui/scrollphasechangecontext/geometry) を使う。別callbackで保持した座標との順序依存を避ける。
- [ ] 原因未確定なら修正せず、検証条件と不足する証拠を記録する。未解決の候補はDeferred Itemsへ移す。

#### Acceptance Criteria

- [ ] 再現結果と因果関係、または修正不要と判断した根拠が記録されている。
- [ ] 修正する場合、旧Deskの操作終了が新Deskの保存位置を上書きしない。
- [ ] Deskごとの手動スクロール位置の復元と、明示的なFocus／中央配置による保存位置解除を維持する。

#### Verification

未実施。所有Deskと失効判断はunit testで検証し、慣性スクロール中のDesk切替は探索確認で補う。
通常のDesk往復だけではこの競合の検証にならない。

---

## Common Acceptance Criteria

- [ ] 明確な原因が確認できた範囲だけ修正する。未再現候補を「修正済み」と記録しない。
- [ ] macOS 26.0を最低対応とし、到達不能な旧OS向け分岐を追加しない。
- [ ] DenStateとlive runtimeの分離、Profile共有状態とwindow-local状態、runtime寿命を維持する。アニメーション調停状態を永続化しない。
- [ ] Board作成の前景／背景の区別、クリックFocus、Den Mode、Deskの保存位置復元を維持する。
- [ ] `DenMotion` 経由のbounce-free motionとReduced Motionを維持する。
- [ ] 新しいテストの前に、バグを一般化した不変条件を記録する。実装詳細や一回限りの再現値を固定しない。
- [ ] `just --list` を確認し、Swift変更後は `just check` を実行する。native入力に影響する場合は該当する既存のfocused UI testも実行する。
- [ ] 少なくとも一回自己レビューする。明確な問題を修正したら関連レビュー・検証を繰り返し、最新の検証成功と対処可能な指摘なしを確認して止める。
- [ ] 各Verificationへ、実行コマンド・結果・再現条件・未確認事項を記録する。
- [ ] 挙動の明確化はDESIGN.mdまたはdocs/shortcuts.md等の所有文書へ反映する。CONTEXT.md／ADRを変える場合はdomain-modelingスキルを使う。
- [ ] 最終差分の不要な抽象化、ドキュメントリンク、重複・古い主張を確認する。

## Deferred Items

現時点ではなし。TASK-012／TASK-013を原因未確定で保留する場合は、IDと未解決事項・検証条件をここに残す。

## Out of Scope

- 今回の台帳更新でのアプリコード変更、タスク実装、コミット。
- 根拠のないアニメーション曲線・時間の調整、Desk切替演出の新設。
- 汎用アニメーションフレームワーク、新規依存、全面的なStore／View分割。
- runtime遅延アタッチ、WebKit／Terminal描画停止、性能改善の再設計。
- 第三者Webサイト、永続化形式、無関係なUX・機能の変更。
