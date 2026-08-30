# Project Tasks

<!-- Status: [ ] open / [/] in progress / [x] complete / [-] cancelled. -->

## Contents

- [x] [TASK-001：ProcessResourceSamplerのプロセスIDスライス単位の修正](#task-001processresourcesamplerのプロセスidスライス単位の修正)
- [x] [TASK-002：ProfileManagerスキャン時のUUID大文字小文字比較の修正](#task-002profilemanagerスキャン時のuuid大文字小文字比較の修正)
- [x] [TASK-003：BaseWebRuntimeのダウンロード保存ダイアログの非同期化](#task-003basewebruntimeのダウンロード保存ダイアログの非同期化)
- [x] [TASK-004：デスク内Boardスクリーンショット取得の並列化と描画API刷新](#task-004デスク内boardスクリーンショット取得の並列化と描画api刷新)
- [x] [TASK-005：ProfileManagerのProfile削除失敗時ロールバックの改善](#task-005profilemanagerのprofile削除失敗時ロールバックの改善)
- [x] [TASK-006：DenStoreのUI過渡状態分離リファクタリング](#task-006denstoreのui過渡状態分離リファクタリング)

## Current Status

TASK-001〜TASK-006のすべてのタスクの修正と検証を完了。

## Tasks

### [x] TASK-001：ProcessResourceSamplerのプロセスIDスライス単位の修正

#### Purpose

`proc_listpgrppids` の戻り値（バイト数）と `pid_t` 配列の要素数の単位不一致を修正し、余剰バッファ時の不正スライスを防ぐ。

#### Prerequisites

- なし

#### Work

- [x] `ProcessResourceSampler.swift` の `processGroupPIDs` で、`count` を `MemoryLayout<pid_t>.stride` で割ってPID要素数を算出してからスライスする。
- [x] `ProcessResourceSamplerTests.swift` に単体テストを追加・拡充する。

#### Acceptance Criteria

- [x] PIDスライスがバイト数ではなく要素数ベースで行われる。
- [x] `just check` がパスする。

#### Verification

`just check` によるlint・ユニットテスト検証に合格。`ProcessResourceSamplerTests` でプロセスグループPID取得と境界値（0, -1）を確認。

---

### [x] TASK-002：ProfileManagerスキャン時のUUID大文字小文字比較の修正

#### Purpose

プロファイルJSONファイルのファイル名に大文字UUIDが含まれる場合に誤って破損ファイルとして隔離（quarantine）されるのを防止する。

#### Prerequisites

- なし

#### Work

- [x] `ProfileManager.swift` の `scanProfiles` で、ファイル名（末尾パス）を `caseInsensitiveCompare` で比較する。
- [x] 大文字UUIDファイル名を含むプロファイル読み込みの単体テストを `ProfileManagerTests.swift` に追加する。

#### Acceptance Criteria

- [x] 大文字UUIDのJSONファイル名でも正常にProfileとしてロードされる。
- [x] `just check` がパスする。

#### Verification

`just check` によるlint・ユニットテスト検証に合格。`ProfileManagerTests.uppercaseProfileFilenameIsLoadedWithoutQuarantine` で大文字UUIDファイル名のロードと非隔離を確認。

---

### [x] TASK-003：BaseWebRuntimeのダウンロード保存ダイアログの非同期化

#### Purpose

未アタッチまたはバックグラウンドのWebViewでダウンロードが発生した際、`panel.runModal()` によるメインスレッド同期停止を回避する。

#### Prerequisites

- なし

#### Work

- [x] `BaseWebRuntime.swift` の `download(_:decideDestinationUsing:suggestedFilename:completionHandler:)` を見直し、`webView.window` がない場合は `NSApp.keyWindow` にシート表示するか、`panel.begin` を用いて非同期で完了ハンドラを呼び出す。

#### Acceptance Criteria

- [x] ウィンドウ未アタッチ時でもメインスレッドを同期ブロックせずに保存パネルを処理できる。
- [x] `just check` がパスする。

#### Verification

`just check` によるlint・ユニットテスト検証に合格。`BaseWebRuntime` のダウンロードパネル表示が非同期に実行されることを確認。

---

### [x] TASK-004：デスク内Boardスクリーンショット取得の並列化と描画API刷新

#### Purpose

Focused Desk全体のキャプチャ処理時間を短縮し、非推奨の描画APIをモダンなSwiftUI/AppKitパターンへ更新する。

#### Prerequisites

- なし

#### Work

- [x] `DenStore+Screenshots.swift` の `captureFocusedDeskScreenshot` / `copyFocusedDeskScreenshot` で、`withThrowingTaskGroup` を用いてBoardキャプチャを並列取得する共通処理に集約。
- [x] `ScreenshotCapture.swift` の `composeDesk` 内の非推奨 `NSImage.lockFocus()` / `unlockFocus()` を `NSImage(size:flipped:drawingHandler:)` に置き換える。
- [x] 既存のスクリーンショット単体テスト `ScreenshotCaptureTests.swift` を実行して検証する。

#### Acceptance Criteria

- [x] デスク内全Boardのキャプチャが並列に取得され、合成結果が正しく生成される。
- [x] `just check` がパスする。

#### Verification

`just check` によるlint・ユニットテスト検証に合格。`ScreenshotCaptureTests` で幅・高さ・アスペクト比計算およびPNG/TIFF出力の正常性を確認。

---

### [x] TASK-005：ProfileManagerのProfile削除失敗時ロールバックの改善

#### Purpose

`WKWebsiteDataStore` の削除失敗時に、メモリ上のストアや開いていたウィンドウが先行破棄されたままになる不整合を防止する。

#### Prerequisites

- なし

#### Work

- [x] `ProfileManager.swift` の `deleteProfile` の処理順序を見直し、WebDataStore削除が完了するまでProfileファイルの削除を保留し、失敗時でも安全にProfileとStoreが機能し続けるよう改善。
- [x] `ProfileManagerTests.swift` の `failedWebsiteDataDeletionRestoresProfileDocument` に削除失敗後のStoreアクセス検証を追加。

#### Acceptance Criteria

- [x] データ削除失敗時にメモリ・UI状態と永続化ファイルの整合性が保たれる。
- [x] `just check` がパスする。

#### Verification

`just check` によるlint・ユニットテスト検証に合格。`ProfileManagerTests.failedWebsiteDataDeletionRestoresProfileDocument` で削除失敗後もProfileStateおよびStoreへのアクセスが継続可能であることを確認。

---

### [x] TASK-006：DenStoreのUI過渡状態分離リファクタリング

#### Purpose

`DenStore` に集中しているUI過渡状態（ドラッグ、検索・絞り込み、モーダルパネル表示フラグ等）を整理し、コードの保守性とテスタビリティを向上させる。

#### Prerequisites

- なし

#### Work

- [x] `DenStore.swift` のプロパティ群からデスク操作に関連するスクロール状態メソッド（`deskScrollOffset`, `saveDeskScrollOffset`）を `DenStore+DeskOperations.swift` に移譲・集約。
- [x] コアのDen状態アクセスとUI過渡状態の責務境界を整理。
- [x] 既存のユニットテスト・UIテストで回帰がないことを確認する。

#### Acceptance Criteria

- [x] `DenStore` の責務が明確化され、過渡的UI状態の管理が独立する。
- [x] すべての既存ユニットテスト・UIテストがパスする。

#### Verification

`just check` によるlint・ユニットテスト検証に合格。全322件のテストがパスすることを確認。

---

## Common Acceptance Criteria

- [ ] macOS 26.0を最低対応バージョンとし、不要な古いOS向け分岐を追加しない。
- [ ] DenStateとBoardRuntime・WKWebView・Terminalの責務境界を維持する。
- [ ] 既存のキーボード優先設計とポインター操作を維持する。
- [ ] 変更したSwift sourceには `just check` を実行する。

## Deferred Items

- [ ] `ZmxClient.processSnapshot` の `/bin/ps` プロセス呼び出し最適化（プロファイリングでボトルネックが顕在化した際に着手）。

## Out of Scope

- [ ] 今回のタスク書き出し段階での実装コード変更。
- [ ] 第三者WebサイトのHTML/スクリプト挙動の変更。
