# Project Tasks

<!-- Status: [ ] open / [/] in progress / [x] complete / [-] cancelled. -->

## Contents

- [x] [TASK-007：Board共通表現の集約](#task-007board共通表現の集約)
- [x] [TASK-008：パネルの状態所有整理](#task-008パネルの状態所有整理)
- [ ] [TASK-009：zmx Sessionsの責務分離](#task-009zmx-sessionsの責務分離)

## Current Status

TASK-001〜TASK-006は実装コミットと完了・検証記録（`64d670b`）を確認し、台帳から削除済み。詳細はGit履歴を参照する。
TASK-006はデスクスクロール操作の移譲（`1e60166`）。今回の責務分離はTASK-007〜TASK-009で扱う。

作業場所は `refactor/view-store-boundaries` worktree。TASK-008まで完了。次はTASK-009。
TASK-007でBoard共通表現を集約し、重複とDenStoreへの依存を差分で確認した。
TASK-008でパネルのdraft・FocusState・送信処理を各パネルへ移し、Open Boardの保持が必要なdraftだけDenStoreのwindow-local状態に残した。

## Purpose and Goals

変更箇所を予測しやすくし、同じ変更の重複と意図しない影響を減らす。行数削減やAtomic化自体は目的にしない。

- Web／Terminal Boardの共通表現を一箇所で変更できる。
- 入力途中の値・フォーカスはパネル、表示切替・確定操作はDenStoreという所有境界を明確にする。
- zmx Sessionsの一覧取得・検索・選択をBoard操作なしで検証できる。
- 既存の入力保持、フォーカス、ドラッグ、パネル排他、複数ウィンドウ、runtime寿命、永続化の振る舞いを維持する。

## Tasks

### [x] TASK-007：Board共通表現の集約

#### Purpose

Web／Terminal Boardで重複する表現・操作を集約し、片方だけの修正による差異を防ぐ。

#### Prerequisites

- なし。実装前に対象コードと呼び出し元を確認し、共通部分と固有部分を確定する。

#### Work

- [x] 枠・影・選択表示を共通Modifierへ、ドラッグヘッダーを小さなViewへ集約する。
- [x] 既存の `BoardHeaderTitle`、`DenPanelHeader`、`.denPanel()` を再利用する。
- [x] 共通部品は必要な値と操作closureを受け取り、DenStoreへの直接依存を避ける。
- [x] Web／Terminal固有の入力処理とnative surfaceの寿命を維持する。

#### Acceptance Criteria

- [x] 共通の枠・影・選択表示・ドラッグヘッダーの変更が一箇所で済む。
- [x] 固有動作を大量の条件分岐や汎用設定へ置き換えていない。
- [x] ドラッグ、アクセシビリティ、Focus Mode、native入力の既存動作を維持する。

#### Verification

`just check` 合格。既存unit test合格。作業中アプリでWeb／Terminal Boardの共通枠、影、選択表示、ドラッグヘッダーを確認。
`CODE_SIGNING_ALLOWED=NO` ではRunnerがテスト本体前に `signal kill` で終了した。署名有効（指定なし）で `testClickingInputOnUnfocusedBoardPreservesClickedResponder` と `testOrganizesBoardsUsingPointer` が合格し、UIテスト失敗原因を確認した。

---

### [x] TASK-008：パネルの状態所有整理

#### Purpose

DenViewの合成責務と、各パネルの編集状態の所有を分け、変更対象をパネル内に絞れるようにする。

#### Prerequisites

- なし。TASK-007とは独立して実装可能。

#### Work

- [x] DenViewと各パネルの入力・フォーカス・送信処理を調べ、現行の入力保持条件を確認する。
- [x] 入力途中の文字列と `FocusState` を各パネルへ寄せる。閉じた後も保持が必要な値は、その寿命を満たす所有場所を明示する。
- [x] パネルの排他表示、Den Mode、確定操作はDenStoreに残す。
- [x] 所有境界を説明する必要がある箇所を `docs/architecture.md` に反映する。

#### Acceptance Criteria

- [x] パネル固有の編集状態・初期化・後始末の所在が明確で、DenViewから不要なBinding中継が減っている。
- [x] 閉じる・再表示・切替・確定・取消で、入力保持とフォーカスの既存動作が変わらない。
- [x] TASK-007と合わせ、重複・依存の削減を最終差分で確認できる。

#### Verification

`just check` 合格。Open Board draftの保持・明示URLによる置換・Board挿入位置の解除をunit testで確認。パネルの状態・FocusState・送信処理は各パネルへ移管し、DenStoreの排他表示と確定APIを維持。
署名有効のUI testは新規DerivedData（`.derived-data-ui-fresh`）で `testClickingInputOnUnfocusedBoardPreservesClickedResponder` が合格。既存`.derived-data-ui`では古いRunner生成物の再利用により起動前`signal kill`となった。

---

### [ ] TASK-009：zmx Sessionsの責務分離

#### Purpose

一覧取得・検索・選択をBoard操作から分け、責務単位で理解・検証できる境界を作る。

#### Prerequisites

- TASK-007、TASK-008の完了と、初回差分での重複・依存削減の確認。

#### Work

- [ ] 一覧取得・検索・選択・非同期Taskを、状態と操作を一緒に持つ専用モデルへ移す。
- [ ] セッション終了処理とパネル表示・非表示時のTask寿命も確認し、所有を明示する。
- [ ] Boardを開く操作とパネル遷移はDenStoreが連携する。
- [ ] `docs/architecture.md` の単一Feature store方針と整合するよう、採用した境界を更新する。ADRの作成・更新が必要なら `domain-modeling` を使う。

#### Acceptance Criteria

- [ ] 一覧取得・検索・選択をDenStoreやBoard runtimeの生成なしで検証できる。
- [ ] 状態だけを移して転送プロパティを並べる分割になっていない。
- [ ] ウィンドウ固有状態、取得失敗、更新競合、閉じた後の非同期結果の扱いを維持する。
- [ ] 既存Boardへのフォーカスと、新規Board作成の動作を維持する。

#### Verification

未実施。専用モデルの意味のある振る舞いとDenStoreとの連携をfocused unit testで検証し、`just check` の結果を記録する。

---

## Common Acceptance Criteria

- [ ] macOS 26.0を最低対応バージョンとし、不要な古いOS向け分岐を追加しない。
- [ ] DenStateとBoardRuntime・WKWebView・Terminalの責務境界を維持する。
- [ ] 既存のキーボード優先設計とポインター操作を維持する。
- [ ] 変更したSwift sourceには `just check` を実行する。
- [ ] Profile共有状態とウィンドウ固有状態の境界を維持し、永続化形式・runtime寿命を変更しない。
- [ ] `docs/testing.md` に従い、実装詳細ではなく意味のある振る舞いを最小のテストで保護する。
- [ ] 差分を自己レビューし、関連検証と問題修正を行い、再レビューで対処可能な問題がなくなるまで繰り返す。
- [ ] 変更したドキュメントのリンク・重複・古い記述を確認する。

## Deferred Items

- [ ] Runtime管理の分離。Profile共有runtimeとウィンドウ別callback再割当の境界を別途調査してから判断する。
- [ ] `ZmxClient.processSnapshot` の `/bin/ps` プロセス呼び出し最適化（プロファイリングでボトルネックが顕在化した際に着手）。

## Out of Scope

- [ ] 今回のタスク書き出し段階での実装コード変更。
- [ ] 第三者WebサイトのHTML/スクリプト挙動の変更。
- [ ] 全Viewの細分化、Atoms／Moleculesの階層導入、Desk／Board別Storeへの機械的分割。
- [ ] 汎用フレームワーク・不要なprotocolやservice層の導入。
- [ ] 性能改善、UI仕様変更、行数削減だけを目的とした変更。
