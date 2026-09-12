# Project Tasks

<!-- Status: [ ] open / [/] in progress / [x] complete / [-] cancelled. -->

## Contents

- [ ] [GHOSTTY-001：upstream mainをForkし配布経路を確立する](#ghostty-001upstream-mainをforkし配布経路を確立する)
- [ ] [GHOSTTY-002：hidden・detached Surfaceのtick寿命をForkで分離する](#ghostty-002hiddendetached-surfaceのtick寿命をforkで分離する)
- [ ] [GHOSTTY-003：Window非attachのexec SurfaceをForkで開始する](#ghostty-003window非attachのexec-surfaceをforkで開始する)
- [/] [GHOSTTY-004：Terminal Cmd-clickのURL actionをForkで完結する](#ghostty-004terminal-cmd-clickのurl-actionをforkで完結する)
- [/] [GHOSTTY-005：DenをFork版へ移行しCLI Terminal Boardを起動する](#ghostty-005denをfork版へ移行しcli-terminal-boardを起動する)
- [/] [GHOSTTY-006：Denの暫定workaroundを削除して統合検証する](#ghostty-006denの暫定workaroundを削除して統合検証する)

## Current Status

2026-09-12時点でForkは未作成。まず`Lakr233/libghostty-spm`の公開最新版を適用し、URL actionとTerminal入力の挙動を確認した。
Denは`libghostty-spm` `1.6.20260909`（`7e45d27160f9b34aca9ca5c9820e9207482f9f04`）と`MSDisplayLink` `2.2.0`を固定している。
最新版の`TerminalController`は、`TerminalSurfaceOpenURLDelegate`を持つhostの`OPEN_URL` actionを処理済みとして返す。これにより、Den側の`TerminalURLSuppressionTracker`、`registerTerminalURL`、`cancelTerminalURLRegistration`ワークアラウンドを削除した。
`den terminal send`、`den terminal run`、`den board terminal new /tmp --run ... --focus`でTerminal入力とcommand実行を実機確認し、テスト用Boardは削除済み。`just check`も成功している。
Den側は既存の`TerminalSurfaceLifecycleDelegate`を利用し、Surface ready前の`--run`を保留してready後に実行するようにした。150ms固定待機は削除済みである。未activate・Detach時にready通知が来ない問題は未解決のまま、別タスクとして扱う。

Fork元は`Lakr233/libghostty-spm`の`main`（`1.6.20260909`、`7e45d27160f9b34aca9ca5c9820e9207482f9f04`）とする。

upstreamはhidden Surfaceのgrid・scrollback・Session維持とoccluded時のwake-up drainを実装済みである。
一方でSurface作成は`AppTerminalView.window != nil`を必要とするため、Boardが未表示でView未生成のCLI経路は解決しない。
透明・画面外`NSWindow`を維持するDen側workaroundは採用しない。

実装開始時に、Fork元revision、Denの未コミット変更、`Package.resolved`、Forkのrelease asset配布先を再確認する。

## Goal

Terminal Sessionの実行寿命を描画Viewのattach状態から分離する。

- CLIで作成したTerminal Boardは、表示・Focus・`NSWindow` attach前に`.exec` Surface、PTY、shellを開始する。
- detachまたは非表示は描画を停止しても、exec Surface、grid、scrollback、PTY、shell、必要な`app_tick`を停止しない。
- 後からBoard Viewをattachしても、Surfaceをrebuildせず、既存のSessionとscrollbackを表示する。
- Surface ready通知をcommand dispatchの同期点とし、固定sleepを置かない。
- `DenState`にはlive Surface、PTY、View、Windowを保存しない。

## Tasks

### [ ] GHOSTTY-001：upstream mainをForkし配布経路を確立する

#### Purpose

最新upstreamのhidden Surface改善を取り込み、Denが再現可能に参照できるForkとbinary XCFramework配布経路を確立する。

#### Work

- [ ] `Lakr233/libghostty-spm`の`main`をForkし、Fork作成時点のupstream revisionを記録する。
- [ ] Fork remoteを追加し、upstream remoteをread-onlyで保持する。Den本体とForkの作業treeを分ける。
- [ ] Forkの`Package.swift`がFork所有のXCFramework release assetとchecksumを参照するようにする。upstream release URLへの暗黙依存を残さない。
- [ ] Forkで`Ghostty.ref`、patch stack、`build.sh`、package testを実行できることを確認する。
- [ ] upstream `main`取り込みとFork固有差分を分離したcommit構成を定める。

#### Acceptance Criteria

- [ ] Forkを新規cloneして依存解決・build・testを再現できる。
- [ ] Fork固有のrelease assetとchecksumがupstream assetに依存しない。
- [ ] Fork差分がSurface lifecycleと必要な配布設定に限定される。

#### Verification

- [ ] Forkから新規cloneし、`swift package resolve`とpackage testを実行する。
- [ ] package release assetを別cloneから取得し、checksumを検証する。

---

### [ ] GHOSTTY-002：hidden・detached Surfaceのtick寿命をForkで分離する

#### Purpose

描画visibility、View attach、`app_tick`を別の寿命として扱い、Denの1秒ごとの`controller.tick()`応急処置を不要にする。

#### Evidence and Entry Points

- current upstreamはoccluded Surfaceのwake-upをdrainするが、detached Surfaceのtickを止める。
- `TerminalSurfaceCoordinator`はSurface lifecycle、metrics、wake-up処理を集約している。
- Denの`TerminalRuntime`はhidden Terminalに対する定期`controller.tick()`応急処置を持つ。

#### Work

- [ ] Surface作成可能条件、描画可能条件、wake-up / `app_tick`実行可能条件を別々に定義する。
- [ ] hidden Surfaceでは描画を止めてもPTY callback、title、PWD、bell、child exitをdrainするFork側経路を実装する。
- [ ] detached exec Surfaceで必要なtickを維持し、attach / visibilityによるrendering停止と混同しない。
- [ ] idle時に不要なdisplay linkやtimerを保持せず、必要なwake-upだけでtickする。
- [ ] Den側の1秒ごとの`controller.tick()`応急処置を削除できるFork API・契約を提供する。

#### Acceptance Criteria

- [ ] hidden / detached状態でも必要なcallbackとchild exitが届く。
- [ ] 描画停止中にper-frame pollingや固定interval timerを常駐させない。
- [ ] Denは独自tick loopなしでTerminal Sessionを維持できる。

#### Verification

- [ ] Fork package testでhidden、detached、idle、child exitの各状態遷移を検証する。
- [ ] AppKit実機でhidden Terminalのresource usageとcallback deliveryを確認する。

---

### [ ] GHOSTTY-003：Window非attachのexec SurfaceをForkで開始する

#### Purpose

透明・画面外Windowを作らず、有効なframeを持つ未attach `AppTerminalView`で`.exec` Surface、PTY、shellを開始する。

#### Prerequisites

- GHOSTTY-002完了。

#### Work

- [ ] `TerminalSurfaceCoordinator.rebuildIfReady()`の`isAttached()`依存を、Surface作成と描画attachの別契約へ置き換える。
- [ ] `NSView`未attach時のmacOS backend resource要件を検証し、wrapperだけで成立するか、raw Ghostty patchが必要かを確定する。
- [ ] `.exec` Surfaceの作成、ready callback、input、output、viewport readをWindow未所属で動作させる。
- [ ] 後からViewをWindowへattachしても同じSurface、child process、grid、scrollbackを維持する。attachでrebuildしない。
- [ ] Surface freeまたはRuntime disposeだけがPTY停止の境界であることを保証する。

#### Acceptance Criteria

- [ ] `NSWindow`未所属のViewで`/bin/zsh -f`を起動し、command outputを読める。
- [ ] attach前後で同一Surface、同一child process、scrollbackが維持される。
- [ ] 固定delay、ポーリング、画面外Window、Window orderingを追加しない。

#### Verification

- [ ] Fork package testで未attach exec、attach後の継続、dispose時の終了を個別に検証する。
- [ ] AppKit実機で未attach開始→attach→disposeを実施し、Crash ReporterとMetal resource警告を確認する。

---

### [ ] GHOSTTY-004：Terminal Cmd-clickのURL actionをForkで完結する

#### Purpose

TerminalのCmd-clickでDenのBoardを作成した後、デフォルトブラウザも開く二重処理をFork側で止める。

#### Work

- [ ] `GHOSTTY_ACTION_OPEN_URL`の`action_cb`で、hostがURLを処理した場合は処理済みを返す契約を実装する。
- [ ] URL action callbackの未処理・拒否・処理済みの戻り値を明確にし、既存プラットフォームのURL挙動を回帰させない。
- [ ] Fork package testでCmd-click URL actionがhostへ一度だけ届き、デフォルトブラウザ起動へfall throughしないことを確認する。

#### Acceptance Criteria

- [x] Denが処理したTerminal URLは、公開最新版からmacOSのデフォルトブラウザへ渡らないことをAppKit実機で確認した。
- [ ] hostが処理しないURLは、既存のfallback方針を維持する。

#### Verification

- [ ] Fork package testでhandled / unhandled / rejected URL actionを検証する。
- [x] AppKit実機でTerminal Cmd-clickを確認する。

---

### [ ] GHOSTTY-005：DenをFork版へ移行しCLI Terminal Boardを起動する

#### Purpose

Fork APIを使い、CLIで作成したTerminal BoardのTerminal SessionをBoard表示前に開始する。

#### Prerequisites

- GHOSTTY-001、GHOSTTY-002、GHOSTTY-003、GHOSTTY-004完了。

#### Work

- [ ] Denのpackage URL、revision、checksumをFork版へ更新し、既存Ghostty API利用箇所を最新APIへ移行する。
- [ ] `DenStore.terminalRuntime(for:)`を唯一のlive Terminal Runtime生成経路として維持する。
- [x] Surface ready前の`--run`を保留し、既存の`TerminalSurfaceLifecycleDelegate`通知後に一度だけ送る。150ms固定待機を削除する。
- [ ] `den board terminal new`でRuntimeとdetached exec Sessionを表示・Focus前に開始する。
- [ ] `den terminal`のinput・signal・viewport・close経路がattach前後で同じTerminal Sessionを対象とすることを確認する。
- [ ] Fork URL action対応後、`TerminalURLSuppressionTracker`、`registerTerminalURL`、`cancelTerminalURLRegistration`を削除する。
- [ ] CLI仕様と所有文書を更新する。`den sheet wait`と異なり、Terminal Board creationはSession開始まで保証することを明記する。

#### Acceptance Criteria

- [ ] `den board terminal new <path> --run <command>`はBoardを表示またはFocusせずにshellを開始し、commandを実行する。
- [ ] 直後にBoardを表示しても新しいPTY、再実行、scrollback消失が起きない。
- [ ] Terminal Cmd-clickでDenのBoardだけが作成され、デフォルトブラウザを開かない。
- [ ] Web Boardの即時runtime起動と既存Terminal Board操作を回帰させない。

#### Verification

- [ ] isolated profileでDenを起動し、CLIからTerminal Boardを作成してmarker commandの実行を確認する。
- [ ] Terminal Runtimeの安定したStore契約をunit testで確認する。native Surface lifecycleはFork package testと実機確認で検証する。
- [x] Swift変更後に`just check`を実行する。

---

### [ ] GHOSTTY-006：Denの暫定workaroundを削除して統合検証する

#### Purpose

Fork経路へ完全に切り替え、Den側にSurface lifecycleを偽装・再実装するworkaroundを残さない。

#### Prerequisites

- GHOSTTY-005完了。

#### Work

- [ ] 未コミットの透明・画面外`NSWindow` bootstrap host、input queue、関連lifecycle補助を削除する。
- [ ] Fork APIが置き換えるhidden tick応急処置を削除する。
- [x] 公開最新版のURL action対応を確認し、Den側のURL suppression workaroundを削除する。
- [ ] CLI Terminal Board作成がForkのdetached exec APIだけで起動するよう呼び出しを整理する。
- [ ] obsolete documentation、backlog項目、テスト用artifactを削除またはFork実装後の事実へ更新する。
- [ ] 変更差分を自己レビューし、Window resource、Surface二重生成、child process leak、固定delayがないことを確認する。

#### Acceptance Criteria

- [ ] Denのproduction codeに透明Window、画面外Window、Window ordering、固定sleep、polling retry、独自tick loop、URL suppression workaroundが残らない。
- [ ] Fork packageとDenの責務境界が明確で、DenはTerminal Sessionのnative lifecycleを再実装しない。
- [ ] Fork不在では不可能だったCLI作成Terminal Board起動が、通常のDen Runtime lifecycle内で動く。

#### Verification

- [ ] `just check`を実行する。
- [ ] CLI作成→未表示でcommand実行→Board表示→output確認→Board削除の実機シナリオを実施する。
- [ ] Terminal Cmd-click、hidden / detach、child exitを実機確認する。
- [ ] 最新のFork revision、実行コマンド、結果、未確認事項を各タスクへ記録する。

## Common Constraints

- macOS 26.0を最低対応とし、到達不能な旧OS fallbackを追加しない。
- Surface、PTY、shell、`NSView`、`NSWindow`、`BoardRuntime`はlive stateであり、`DenState`へ永続化しない。
- CLI commandの成功応答とTerminal Session readyを混同しない。`--run`はSurface ready callbackを待つ。
- `.exec` backendを維持する。host-managed I/Oで既存PTYを再実装しない。
- Forkはupstream `main`からの変更を最小に保ち、upstream追従可能なcommit構成にする。
- Fork・Den双方で、実行した検証、実機条件、既知の制約を記録する。

## Out of Scope

- この台帳更新でのFork作成、GitHub release作成、依存更新、アプリコード変更、コミット。
- raw Ghostty本体へのForkまたはpatch。`libghostty-spm`側だけで成立しないと実証された場合に限り再検討する。
- transparent / offscreen `NSWindow`を恒久対策として採用すること。
- PTY transportをDenで再実装するための`InMemoryTerminalSession`移行。
- 無関係なTerminal UI、Desk、Web Board、永続化形式の変更。
