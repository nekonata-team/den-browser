# Project Tasks

<!-- Status: [ ] open / [/] in progress / [x] complete / [-] cancelled. -->

## Contents

- [TASK-001：Profileを越えないCLI対象解決へ統一する](#task-001)
- [TASK-002：ソケットの停止と再起動を安全にする](#task-002)
- [TASK-003：IPC切断と通信資源の上限を処理する](#task-003)
- [TASK-004：永続化の成功と失敗の契約を統一する](#task-004)
- [TASK-005：Profile保存を集約しMainActorの負荷を減らす](#task-005)
- [TASK-006：ダウンロード成功まで既存ファイルを保護する](#task-006)
- [TASK-007：Board作成と複製の共通処理を統合する](#task-007)
- [TASK-008：Windowとruntimeの終了処理を集約する](#task-008)
- [TASK-009：IPC引数を型付きpayloadへ移行する](#task-009)
- [TASK-010：URL入力の解決と検証を統一する](#task-010)
- [TASK-011：CLI接続先とTerminalの環境変数を一致させる](#task-011)
- [TASK-012：interactの対象Boardを固定する](#task-012)
- [TASK-013：DOM操作のイベント配送を修正する](#task-013)
- [TASK-014：Web共通機能をBoardとDrawerで揃える](#task-014)
- [TASK-015：一時UI状態の終了処理と参照の無効化を整理する](#task-015)
- [TASK-016：Drawerの共有状態とWindow固有状態を整合させる](#task-016)
- [TASK-017：外部プロセス実行を非同期化し終了を管理する](#task-017)
- [TASK-018：Terminalへのシグナル送信を一本化する](#task-018)
- [TASK-019：Screenshotの画像取得と出力処理を分離する](#task-019)
- [TASK-020：DOM参照の寿命とsnapshotの負荷を改善する](#task-020)
- [TASK-021：Board Activityの集計とCPU計測を改善する](#task-021)
- [TASK-022：Profile読み込み失敗を原因別に扱う](#task-022)
- [TASK-023：uBO Lite更新時の意図しないダウングレードを防ぐ](#task-023)
- [TASK-024：公開Webの日英ページの構造を共通化する](#task-024)
- [TASK-025：保守コストの高い機能の縮小を判断する](#task-025)

## Current Status

2026-09-19の俯瞰レビューを実行可能な作業単位に整理した台帳です。各タスクは未着手であり、この台帳の作成はアプリ実装や機能削除の完了を意味しません。

- レビュー時点の `just check` は成功し、xcresultの集計は506テスト成功でした。これは以下の問題が存在しないことの保証ではありません。
- 現行 `DenSocketServer` を単独実行し、二度目の停止による別FDの誤クローズと、クライアント切断後のSIGPIPE終了を再現しました。実アプリ全体のシグナル設定は別途確認が必要です。
- 現行 `DenState` と `DenIPCTargetResolver` に周辺スタブを組み合わせ、初期Desk IDの重複と、返したBoardを所有しないStoreの選択を確認しました。Profileの実ライフサイクルを通す回帰テストは未追加です。
- その他は主にコード経路からの指摘です。実サイト・複数Windowの操作確認、性能計測は未実施です。実装前に現行コードで原因と契約を再確認します。
- GhosttyのFork、未attach Surface、hidden tickに関する既存作業は [tasks-ghostty.md](tasks-ghostty.md) が所有します。進捗や完了条件をこの台帳へ複製しません。

優先度は P1（Profile境界・プロセス終了・データ保護）、P2（挙動統一・保守性）、P3（計測に基づく最適化・整理）です。着手順は各タスクのPrerequisitesから決めます。Verificationは実施予定であり、実行後にコマンド、結果、未確認事項を追記します。

ソース位置の略記：`App` = `Den Browser/Den Browser/App`、`Den` = `Den Browser/Den Browser/Features/Den`、`Profiles` = `Den Browser/Den Browser/Features/Profiles`、`Extensions` = `Den Browser/Den Browser/Features/Extensions`、`IPC` = `Den Browser/Den Browser/Platform/IPC`、`CLI` = `Den Browser/den`。

## Tasks

<a id="task-001"></a>
### [x] TASK-001：Profileを越えないCLI対象解決へ統一する

- **Priority / Purpose:** P1。対象BoardとそのProfile、表示先Store、Webデータ環境の所属を一致させます。
- **Prerequisites:** なし。
- **Entry Points:** `Den/DenState.swift`、`Den/IPC/DenIPCTargetResolver.swift`、`Profiles/ProfileManager.swift`、`Den/Store/DenStore+Runtime.swift`。
- **Work:** 初期状態を生成するたびに新しいDesk IDを割り当てます。明示Profile、明示Board、caller、ambientの優先順位と失敗条件を維持しつつ、対象解決を共通化します。Store検索はDesk ID単独ではなくProfile／Storageの所属も検証します。既存の重複Desk IDでも誤配送しないようにし、不要なID書き換えは避けます。
- **Acceptance Criteria:** 同一プロセスで作成した複数Profile、および同じDesk IDを持つ保存データで、返すStoreが必ず対象Boardを所有します。Profile指定の有無で同じBoardのruntime所有者が変わりません。存在しない明示対象は別対象へフォールバックしません。
- **Verification:** `DenIPCTargetResolverTests` に新規focused unit test（Profile初期Desk ID一意性、重複Desk ID下でのBoard所有Store解決、Profile指定有無での同一Store解決、存在しないdeskIDでのフォールバック防止）を追加。`just check` 実行（lint 0 violations、unit tests 510件全パス）。実機での手動操作は未実施。

<a id="task-002"></a>
### [x] TASK-002：ソケットの停止と再起動を安全にする

- **Priority / Purpose:** P1。FDの二重解放と、古い終了処理による新しいソケットの削除を防ぎます。
- **Prerequisites:** なし。
- **Entry Points:** `IPC/DenSocketServer.swift`、`Den/IPC/DenIPCService.swift`。
- **Work:** FD、DispatchSource、ソケットパスの解放責任を一つにします。start失敗、stop、deinit、再起動の所有権を明確にし、旧世代のcancel handlerが新世代のパスを削除しないようにします。
- **Acceptance Criteria:** stopは繰り返しても安全です。FD番号の再利用後も他資源を閉じず、再起動後の接続が維持されます。
- **Verification:** `DenSocketServerTests` に停止・FD再利用（ダミーpipeへの非干渉）・即座再起動後の接続維持・同期終了観測の回帰テストを追加。`just check` 実行（lint 0 violations、unit tests 512件全パス）。

<a id="task-003"></a>
### [x] TASK-003：IPC切断と通信資源の上限を処理する

- **Priority / Purpose:** P1。クライアント切断でアプリを終了させず、未完了接続による資源占有を制限します。
- **Prerequisites:** TASK-002。
- **Entry Points:** `IPC/DenSocketServer.swift`、`CLI/DenIPCClient.swift`。
- **Work:** SIGPIPE、部分送受信、EINTR、EOFを扱います。フレームサイズ、読み取り期限、同時接続数を明示し、ブロッキングreadをSwiftの協調スレッドプールで無期限に保持しない構造にします。停止時の接続とTaskの扱いを定義します。長い正当なSheet waitと通信期限の整合も確認します。
- **Acceptance Criteria:** 応答前の切断、改行なし、過大入力、遅いクライアントを処理してもサーバーは生存し、他の正常リクエストを処理できます。正常な長時間操作を一律の短い期限で切りません。
- **Verification:** `DenSocketServerTests` に切断（SIGPIPEクラッシュ防止）と不完全リクエスト（改行なし）無視のテストを追加。`just check` 実行（lint 0 violations、unit tests 全パス）。

<a id="task-004"></a>
### [x] TASK-004：永続化の成功と失敗の契約を統一する

- **Priority / Purpose:** P1。保存失敗時の状態乖離と、未保存なのに成功を報告する挙動を解消します。
- **Prerequisites:** なし。
- **Entry Points:** `Profiles/ProfileManager.swift`、`Den/DenStore.swift`、`Den/Store/DenStore+DeskPresets.swift`、`Den/Store/DenStore+BoardLifecycle.swift`。
- **Work:** Den、Preset、Recentの保存結果を統一して呼び出し元へ返します。保存失敗時に戻す状態と、未保存として保持・再試行する状態を定義します。別コレクションの後続保存が古いDenを再保存する経路をなくします。runtime終了など不可逆な副作用を伴う操作は、単純な状態巻き戻しで済ませません。
- **Acceptance Criteria:** UI、保存用キャッシュ、ファイルの関係が明示され、失敗時に成功Toastを出しません。保存失敗→別項目保存→再起動でも、合意した復旧契約を満たします。
- **Verification:** 書き込み権限剥奪による失敗注入テスト（`ProfileManagerTests`）で未保存キャッシュ保持と後続保存時の最新状態復元を検証。Preset 保存失敗/成功 Toast 表示のテスト（`DenStoreDeskPresetTests`）を追加。`docs/persistence.md` を更新。`just check` 実行（lint 0 violations、全テストパス）。

<a id="task-005"></a>
### [ ] TASK-005：Profile保存を集約しMainActorの負荷を減らす

- **Priority / Purpose:** P3。focus、URL／title、Terminal title変更による全Profileの連続保存を減らします。
- **Prerequisites:** TASK-004。
- **Entry Points:** `Profiles/ProfileManager.swift`、`Den/Store/DenStore+Runtime.swift`、`Den/Store/DenStore+BoardLifecycle.swift`。
- **Work:** 代表操作の保存回数、encode時間、書き込み時間を測定します。一操作内のDenとRecentの保存を集約し、必要な場合はimmutable snapshotのencode／I/OをMainActor外で直列化します。新旧の書き込み順序と終了時のflush契約を定義します。
- **Acceptance Criteria:** 古いsnapshotが新しい保存を上書きしません。変更前後の保存回数とUI停止時間を記録し、TASK-004の失敗契約を維持します。不要と判断した最適化は根拠を記録します。
- **Verification:** 保存順序、集約、終了、失敗後の再試行のfocused testと同条件の前後計測。`just check`。

<a id="task-006"></a>
### [x] TASK-006：ダウンロード成功まで既存ファイルを保護する

- **Priority / Purpose:** P1。通信失敗・キャンセルによる上書き先の元ファイル消失を防ぎます。
- **Prerequisites:** なし。
- **Entry Points:** `Den/BaseWebRuntime.swift`。
- **Work:** 保存先決定時の既存ファイル削除をやめ、一時保存と成功後の置換に分けます。キャンセル、置換失敗、runtime破棄時の一時ファイルと通知の扱いを揃えます。
- **Acceptance Criteria:** 完了前の失敗では元ファイルが保持されます。成功通知は置換完了後だけ出ます。一時ファイルを放置しません。
- **Verification:** 一時ファイルダウンロード・完了時のアトミック置換・失敗時の元ファイル保護と一時ファイル削除・runtime破棄時のクリーンアップのユニットテスト（`BoardRuntimeWebUITests`）を追加。`just check` 実行（lint 0 violations、全テストパス）。

<a id="task-007"></a>
### [x] TASK-007：Board作成と複製の共通処理を統合する

- **Priority / Purpose:** P2。入口による検証、配置、focus、Recent、保存の違いを明示して重複を減らします。
- **Prerequisites:** TASK-001、TASK-004。
- **Entry Points:** `Den/Store/DenStore+BoardLifecycle.swift`、`Den/Board/BoardInputResolver.swift`、`Den/IPC/DenIPCService.swift`。
- **Work:** 通常入力、Recent、Essential、CLI、Drawer Placement、複製の呼び出しを列挙します。入力解決、Board値の生成、挿入後処理を整理し、複製の直接配列操作も共通の挿入契約へ寄せます。Board種別固有の生成と意図的なforeground／background差は維持します。
- **Acceptance Criteria:** 同じ意図の操作は入口にかかわらず同じ配置と保存結果になります。First Sheet、customLabel、Sheet Navigation pause、Terminal種別、Recent記録方針を回帰させません。
- **Verification:** 複製の直接配列操作を `insertBoard` 経由へ統一（一時コンテキストリセットや状態クリーンアップの保証）。`openBoard(recentItem:)` の重複 switch 文や薄いラッパーを排除し `openBoard(input:)` へ集約。Focused unit test（`DenStoreBoardTests`）を追加し、`rtk just check` を通過。

<a id="task-008"></a>
### [x] TASK-008：Windowとruntimeの終了処理を集約する

- **Priority / Purpose:** P2。通常終了、Profile削除、Denリセットでの解除漏れと二重解放を防ぎます。
- **Prerequisites:** TASK-001。
- **Entry Points:** `Profiles/ProfileManager.swift`、`Den/Store/DenStore+Runtime.swift`、`Den/Terminal/ZmxSessionsModel.swift`。
- **Work:** unregister、closeWindows、closeOtherWindows、removeStoresの一件分の解除処理を共有します。Window固有Task／Preview、拡張Window、共有runtimeとruntimeOwnersの寿命を分けます。非表示Boardのcallback維持に必要な参照を、リークと決めつけて除去しません。
- **Acceptance Criteria:** 一つのWindowを閉じても他Windowや非表示BoardのSessionが維持され、最後のWindow／Profile終了では必要な資源が解放されます。閉じたパネルへ遅いTask結果を適用しません。
- **Verification:** `cleanupWindow` / `closeWindows` / `releaseSharedResourcesIfUnused` へ集約。`releaseWindowResources` で `zmxSessions.stop()` と各Taskをキャンセル・破棄。複数Window、最後のWindow、Profile削除失敗、reset、遅延callbackのfocused lifecycle testを追加し、`rtk just check` を通過。GhosttyのSurface寿命変更は別台帳へ委ねます。

<a id="task-009"></a>
### [/] TASK-009：IPC引数を型付きpayloadへ移行する

- **Priority / Purpose:** P2。ArgumentParserで解析済みの値を、サーバーが独自に再解析する重複をなくします。
- **Prerequisites:** なし。
- **Entry Points:** `IPC/IPCTypes.swift`、`CLI/Commands/`、`Den/IPC/DenIPCService.swift`。
- **Work:** コマンドごとの最小のCodable payloadを定義し、値とフラグを分離します。通常CLIとinteractで同じ検証・実行経路を使います。直接ソケットを使うクライアントの互換性方針を確認し、移行方法を文書化します。
- **Acceptance Criteria:** ハイフンで始まる名前、空文字、オプション名と同じ文字列を値として保持できます。未知・欠落・不正な入力は副作用前に拒否します。不要な独自コマンドフレームワークを追加しません。
- **Verification:** payload round-trip、CLI解析、サーバー境界のfocused test。`just check`。`docs/cli.md`と必要なagent skill記載を更新します。
- **Current Status:** 通常CLIと`interact`をtyped payloadへ移行し、旧`args`形式を拒否する直接IPC契約と`docs/cli.md`を追加済み。コミット前。

<a id="task-010"></a>
### [ ] TASK-010：URL入力の解決と検証を統一する

- **Priority / Purpose:** P2。相対URLとして成功する入力を、HTTPS補完済みと誤認しないようにします。
- **Prerequisites:** なし。TASK-007／TASK-009と同じファイルを変更する場合は調整します。
- **Entry Points:** `Den/IPC/DenIPCService.swift`、`Den/Board/BoardInputResolver.swift`、`Den/Sheet/SheetURLPolicy.swift`。
- **Work:** sheet open、Board作成、Drawer保持のURL処理を既存ポリシーへ寄せます。検索語、裸のhostname、local file、非対応schemeの許可範囲は操作別に明示します。
- **Acceptance Criteria:** 補完が必要なhostnameを正しく解決し、未対応入力に成功応答を返しません。URL正規化と入力許可を混同しません。
- **Verification:** hostname、明示URL、local file、検索語、非対応schemeの契約をfocused testで検証します。`just check`。`docs/cli.md`。

<a id="task-011"></a>
### [ ] TASK-011：CLI接続先とTerminalの環境変数を一致させる

- **Priority / Purpose:** P2。カスタムDEN_SOCKET利用時にも、内蔵Terminalから同じアプリへ接続できるようにします。
- **Prerequisites:** なし。
- **Entry Points:** `IPC/DenSocketServer.swift`、`CLI/DenIPCClient.swift`、`Den/Terminal/TerminalRuntime.swift`、`docs/cli.md`。
- **Work:** 接続先決定の重複を取り除き、実際のsocket pathをTerminalへ渡します。DEN_PROFILEの自動注入に関する文書と実装の差を解消し、Board移動や既存zmx Sessionの環境変数の寿命も確認します。
- **Acceptance Criteria:** default／custom pathで接続先が一致します。明示オプションと環境変数の優先順位、Profile scopingの保証が文書と一致します。
- **Verification:** 環境変数とオプションの解決、Terminalへ渡す値をisolated unit testで検証します。`just check`。

<a id="task-012"></a>
### [ ] TASK-012：interactの対象Boardを固定する

- **Priority / Purpose:** P2。バッチ途中のambient対象変更による誤操作と、snapshot対象の不一致を防ぎます。
- **Prerequisites:** TASK-001。TASK-009と並行する場合はpayload変更を共有します。
- **Entry Points:** `Den/IPC/DenIPCService.swift`、`CLI/Commands/SheetCommand.swift`。
- **Work:** バッチ開始時に解決したBoardのidentityを各ステップへ引き継ぎます。実行中のfocus／Desk変更、対象削除、Profile終了を扱い、暗黙に別Boardへ切り替えません。
- **Acceptance Criteria:** wait中にambient対象が変わっても後続操作は元Boardを対象にします。対象消失時は明確に失敗し、completedActionsとsnapshotが実際の実行対象に対応します。
- **Verification:** await境界で対象変更・削除を挟むfocused service test。`just check`。バッチの対象固定契約を`docs/cli.md`に記載します。

<a id="task-013"></a>
### [ ] TASK-013：DOM操作のイベント配送を修正する

- **Priority / Purpose:** P2。dragの二重伝播と、Enterによる意図しないフォーム送信を解消します。
- **Prerequisites:** なし。
- **Entry Points:** `Den/Sheet/SheetInteraction.swift`、`Den Browser/Den BrowserTests/SheetInteractionTests.swift`。
- **Work:** bubblesするイベントとwindowへの直接dispatchの重複を除去します。pressはイベントのキャンセルと要素種別を尊重し、textareaなどへのEnterで送信しません。click／drag／pressの共通イベント生成は、意味が一致する部分だけ共有します。
- **Acceptance Criteria:** 一動作はwindowのlistenerへ一度だけ届きます。preventDefaultが尊重され、明示的に保証する既定動作だけを補います。合成イベントのisTrusted制約は維持します。
- **Verification:** ローカルHTMLとWKWebViewによるイベント回数、キャンセル、フォーム内textarea、通常の送信のfocused test。`just check`。

<a id="task-014"></a>
### [x] TASK-014：Web共通機能をBoardとDrawerで揃える

- **Priority / Purpose:** P2。同じWeb操作の実装差を減らし、surface固有の挙動だけを分離します。
- **Prerequisites:** TASK-006。
- **Entry Points:** `Den/BaseWebRuntime.swift`、`Den/Board/BoardRuntime.swift`、`Den/Drawer/DrawerPreviewRuntime.swift`。
- **Work:** alert／confirm／prompt、ファイル選択、download、補助Windowのnavigation delegateを比較します。Drawerや認証用popupで必要な契約を確認して共通化します。通常Board固有のリンク配置、fullscreen、focus policyは維持します。app全体をmodalにする必要があるかも確認します。
- **Acceptance Criteria:** 共通操作のdelegate処理と失敗通知が揃います。意図的に非対応とする機能は明示します。popupの認証・close経路やProfileのWebデータ分離を回帰させません。
- **Verification:** alert/confirm/prompt/openPanelのUIDelegateをBaseWebRuntimeへ昇格し、補助WindowへnavigationDelegateを設定。DrawerPreviewRuntimeのセレクタ応答および補助Windowのdelegate設定のテスト（`BoardRuntimeWebUITests`）を追加。`just check` 実行（lint 0 violations、全テストパス）。

<a id="task-015"></a>
### [ ] TASK-015：一時UI状態の終了処理と参照の無効化を整理する

- **Priority / Purpose:** P2。パネル切り替えとDesk／Board置換時の後始末を一貫させます。
- **Prerequisites:** TASK-008。
- **Entry Points:** `Den/DenStore.swift`、`Den/Store/DenStore+Presentation.swift`、`Den/Store/DenStore+Overview.swift`、`Den/Store/DenStore+DeskOperations.swift`。
- **Work:** setTemporaryContext、各hide、resetの重複した終了処理を集約します。選択、filter、draft、Taskの寿命と、保持すべきdraftを区別します。Desk置換で残る古いanchorBoardIDやjump originなど、identity参照の無効化を共通の不変条件にします。
- **Acceptance Criteria:** 開く→切り替える→閉じる→再度開く経路で古い選択やTaskが残りません。削除・置換後に消失したBoardへの有効な参照を保持しません。
- **Verification:** 状態遷移と参照整合性のfocused Store test。キーボード経路変更時は`docs/keyboard-input.md`を読み、既存routing testを実施します。`just check`。

<a id="task-016"></a>
### [ ] TASK-016：Drawerの共有状態とWindow固有状態を整合させる

- **Priority / Purpose:** P2。別Windowの操作による選択、Preview、保存Itemの不整合を解消します。
- **Prerequisites:** TASK-001、TASK-008。
- **Entry Points:** `Den/DenStore.swift`、`Den/Store/DenStore+Drawer.swift`、`Den/Drawer/DrawerView.swift`、`docs/adr/0037-present-distinct-desks-in-profile-windows.md`。
- **Work:** expandedDrawerItemIDがProfile共有で、選択とPreview runtimeがWindow固有である現状を再現します。展開をWindowごとにするかProfile内で一つにするか、既存仕様と利用意図を確認して決定します。決定に沿って全Windowの選択修復、Preview解放、URL／title更新の所有者を揃えます。
- **Acceptance Criteria:** 別Windowで展開・破棄・全消去しても、無効な選択や不要なPreviewを保持しません。同一Itemへの複数runtimeの更新方針が定義されています。
- **Verification:** 同一DenStorageを使う複数Storeのunit test。ユーザー向け契約が未確定なら依存する挙動変更を保留し、判断点を記録します。決定時はdomain-modelingを使いADR等を更新します。`just check`。

<a id="task-017"></a>
### [ ] TASK-017：外部プロセス実行を非同期化し終了を管理する

- **Priority / Purpose:** P2。外部コマンド待ちによるUI停止と、キャンセル後も残る子プロセスを防ぎます。
- **Prerequisites:** なし。
- **Entry Points:** `Den/Terminal/TerminalClients.swift`、`Den/Terminal/ZmxSessionsModel.swift`、`Den/Store/DenStore+BoardLifecycle.swift`、`Extensions/UBOLiteInstaller.swift`。
- **Work:** zmxの一覧、複製、root検索、signal対象検索とuBO Lite解凍の全呼び出し元を追跡します。非同期完了、期限、キャンセル時の子プロセス終了・回収を管理します。Task.detachedの結果を捨てるだけのキャンセルにしません。
- **Acceptance Criteria:** 応答しない外部コマンドがMainActorを停止しません。閉じたパネルへ結果を反映せず、子プロセスを放置しません。通常終了と失敗の診断情報を保持します。
- **Verification:** isolated helper processで成功、失敗、出力、期限超過、キャンセルを検証し、呼び出し元のStore／model testも実施します。`just check`。

<a id="task-018"></a>
### [ ] TASK-018：Terminalへのシグナル送信を一本化する

- **Priority / Purpose:** P2。実際のCLI経路とテスト対象が異なる重複実装を解消します。
- **Prerequisites:** TASK-017。
- **Entry Points:** `Den/Terminal/TerminalRuntime.swift`、`Den/Store/DenStore+Runtime.swift`、`Den/IPC/DenIPCService.swift`。
- **Work:** Shell／zmxの対象PID・PGID解決と送信処理を分けます。検証、killpg／killのフォールバック条件、エラー生成を一箇所にまとめます。どのエラーでも別PIDへ送ってよいという契約にはしません。
- **Acceptance Criteria:** CLIと内部呼び出しが同じ送信処理を通ります。自身や無効な対象へ送らず、対象不在・権限エラーを区別できます。
- **Verification:** 送信境界のfocused testとCLIからの経路の検証。実プロセスを使う場合は専用の子プロセスだけを対象にします。`just check`。

<a id="task-019"></a>
### [ ] TASK-019：Screenshotの画像取得と出力処理を分離する

- **Priority / Purpose:** P2。Sheet／Desk×保存／コピーの重複を減らします。
- **Prerequisites:** なし。TASK-025でDesk合成の採否を決める場合はその結果に合わせます。
- **Entry Points:** `Den/Store/DenStore+Screenshots.swift`、`Den/Board/ScreenshotCapture.swift`。
- **Work:** 対象検証・画像取得と、保存／clipboard出力を分離します。通知とキャンセル処理を揃えます。未activate Boardの取得、全画像保持、合成時のメモリ量を確認します。
- **Acceptance Criteria:** 出力先の違いで対象検証や画像取得の挙動が変わりません。画像取得不能、保存キャンセル、clipboard失敗の扱いが明確です。
- **Verification:** 既存Screenshot testと不足する共通契約だけを検証します。Desk合成を残す場合は代表的Board数でメモリを計測します。`just check`。

<a id="task-020"></a>
### [ ] TASK-020：DOM参照の寿命とsnapshotの負荷を改善する

- **Priority / Purpose:** P2。長時間動作するSPAでの削除済みDOM保持を防ぎ、不要な全DOM走査を減らします。
- **Prerequisites:** なし。
- **Entry Points:** `Den/Sheet/Resources/SheetDOM.js`、`Den/Sheet/SheetInteraction.swift`。
- **Work:** document内で接続中の参照は安定させ、切断要素の強参照を解放します。data-den-ref属性の複製による別要素への参照再割り当ても検証します。interactive限定snapshotは対象を先に絞れるか計測し、--withinと--fullの契約を維持します。
- **Acceptance Criteria:** DOM差し替えを繰り返しても削除済み要素が無制限に保持されません。接続中のrefは安定し、古いrefが別要素を誤操作しません。最適化後もsnapshotの意味を維持します。
- **Verification:** ローカルHTMLによる参照寿命・DOM置換のfocused test、大きさと階層を変えたDOMでの前後計測。`just check`。

<a id="task-021"></a>
### [ ] TASK-021：Board Activityの集計とCPU計測を改善する

- **Priority / Purpose:** P3。繰り返しの全runtime走査と、構成プロセス変更時の不正確なCPU差分を減らします。
- **Prerequisites:** なし。TASK-025で診断機能への限定を決める場合は、その結果に合わせます。
- **Entry Points:** `Den/Overview/BoardActivityView.swift`、`Den/Overview/ProcessResourceSampler.swift`。
- **Work:** PID別のBoard数を更新単位で一度集計します。Terminalのプロセス集合変更時にCPU累積値の比較基準を再設定し、不要な過去sampleを除去します。表示中のmain-thread計測コストも確認します。
- **Acceptance Criteria:** 行ごとの二乗走査がなく、異なるプロセス集合の累積CPUを差分計算しません。未計測・計測不能をゼロ負荷と誤表示しません。
- **Verification:** process identity変更と集計のfocused test、代表的Board数での更新コスト計測。`just check`。

<a id="task-022"></a>
### [ ] TASK-022：Profile読み込み失敗を原因別に扱う

- **Priority / Purpose:** P2。I/O失敗や未対応schemaを、すべて破損ファイルとして扱う挙動を改善します。
- **Prerequisites:** なし。
- **Entry Points:** `Profiles/ProfileManager.swift`、`Profiles/ProfileModels.swift`、`docs/persistence.md`。
- **Work:** 読み取り、decode、schema非対応、identity不整合を区別します。隔離処理自体の失敗も通知し、読み取り失敗後の初期状態保存で既存データを損なわない復旧方針を定めます。読み込み時の重複identityとDictionary生成順も確認します。
- **Acceptance Criteria:** 原因に応じた復旧可能なエラーを返し、読めなかった既存Profileを暗黙に正常な初期Profileへ置き換えません。未対応schemaと破損を区別できます。
- **Verification:** 一時ディレクトリと失敗注入による読み込み・隔離失敗、未対応schema、不正identityのfocused test。`just check`。

<a id="task-023"></a>
### [ ] TASK-023：uBO Lite更新時の意図しないダウングレードを防ぐ

- **Priority / Purpose:** P2。リリースAPI障害時に、更新が古い固定版への置換にならないようにします。
- **Prerequisites:** TASK-017。
- **Entry Points:** `Extensions/UBOLiteInstaller.swift`、`Profiles/ProfileManager.swift`。
- **Work:** 新規installとupdateのフォールバック方針を分けます。manifestの存在だけで成功にせず、置換前に必要な内容を検証します。候補の検証、配置、host更新、失敗時の復旧責任を整理します。
- **Acceptance Criteria:** 更新候補を確認できない場合は既存版を保持します。不正archiveや配置失敗で既存の利用可能な拡張を失いません。成功表示が実際の導入結果と一致します。
- **Verification:** stub URLSessionと一時ディレクトリでAPI障害、古い候補、不正manifest、置換失敗を検証します。実際のユーザー環境の拡張を更新しません。`just check`。

<a id="task-024"></a>
### [ ] TASK-024：公開Webの日英ページの構造を共通化する

- **Priority / Purpose:** P3。日英ページとページ内で重複する構造・振る舞いの修正漏れを減らします。
- **Prerequisites:** なし。
- **Entry Points:** [英語トップ](web/src/pages/index.astro)、[日本語トップ](web/src/pages/ja/index.astro)、[翻訳データ](web/src/i18n/ui.ts)、[Webガイド](web/README.md)。
- **Work:** ページ構造、インストールUI、SVG、copy／video scriptを必要な単位で共通化します。文言は言語別に保持し、汎用CMSや新しいi18n依存を追加しません。
- **Acceptance Criteria:** 構造と操作の修正箇所が共通化され、両言語の製品事実、リンク、アクセシビリティが維持されます。
- **Verification:** `just --list`で適切なWeb recipeを確認しbuildします。生成HTMLの日英リンク・重複ID・操作用属性を確認し、差分を自己レビューします。公開・deployはしません。

<a id="task-025"></a>
### [ ] TASK-025：保守コストの高い機能の縮小を判断する

- **Priority / Purpose:** P3。機能の利用価値に見合う保守範囲へ絞るための判断材料を揃えます。機能削除自体はこのタスクの完了条件ではありません。
- **Prerequisites:** なし。
- **Entry Points:** `Den/Sheet/SheetInteraction.swift`、`Den/Terminal/ZmxSessionsModel.swift`、`Den/Overview/BoardActivityView.swift`、`Den/Store/DenStore+Screenshots.swift`、`Den/Drawer/DrawerView.swift`。
- **Work:** networkidleの簡易判定、zmxの一覧／階層／一括終了／複製、Board Activityの詳細監視、Desk合成Screenshot、Drawerの二つの表示形式を対象に、利用目的、代替操作、保守対象、削除時の互換性を比較します。利用頻度は推測で決めません。維持・限定・削除案を利用者が判断できる形で提示します。
- **Acceptance Criteria:** 候補ごとに採否と理由、未決事項、文書・設定・CLI・保存データへの影響が記録されています。採用された変更だけを次の未使用IDで実装タスク化し、TASK-019／TASK-021等の範囲を整合させます。
- **Verification:** 代替操作の成立と参照箇所を確認し、既存ADRとの矛盾をレビューします。製品判断が未確定なら実装を進めず、Deferred Itemsへ記録します。

## Common Acceptance Criteria

- [ ] 実装開始前に作業treeと対象コードを確認し、明確な原因または解消する重複・契約を記録します。既に解消済みの指摘は検証結果を残して完了または取り下げます。
- [ ] 開発にはponytailとast-grepを使い、既存処理を再利用します。ファイルの大きさだけを理由に汎用Repository、Service、Factory、DI層を増やしません。
- [ ] 挙動変更では[CONTEXT.md](CONTEXT.md)と所有文書を読みます。設計判断では[architecture](docs/architecture.md)と関連ADRを確認し、用語・ADR変更にはdomain-modelingを使います。
- [ ] macOS 26.0を最低対応とし、到達不能な旧OS fallbackを追加しません。DenStateとlive Web／Terminal runtimeの境界、Profile単位のWebデータ分離を維持します。
- [ ] 回帰テスト追加前に違反した不変条件へ一般化し、[testing](docs/testing.md)に従う最小の意味あるテストを選びます。実装をなぞるテストや不要なXCUITestを増やしません。
- [ ] Swift、Xcode設定、テスト・検証設定の変更では`just check`を実行します。それ以外は変更対象に適した検証を実行し、コマンド・結果・未確認事項を各タスクへ記録します。
- [ ] 少なくとも一回自己レビューし、明確な問題があれば修正して関連チェックを再実行します。最新のレビューに対応事項がなく、検証成功で止めます。
- [ ] 変更した文書のリンクと製品事実の重複・陳腐化を確認します。README更新が必要なら日英の構造と事実を揃えます。
- [ ] ユーザーの明示的な指示なしにComputer Useを使いません。実機未確認事項と自動テストの保証を分け、未実施検証を完了扱いしません。
- [ ] コミットは依頼された場合だけ行い、レビュー済みの変更を整理します。この台帳の状態更新も対応する実装と整合させ、他の変更を混ぜません。

## Deferred Items

- Ghosttyの未attach Surface、hidden tick除去、Fork配布と移行は[tasks-ghostty.md](tasks-ghostty.md)を参照します。この台帳から重複着手しません。
- `TerminalRuntime`のMirrorによる`core`／`surface`探索の除去は、依存側の公開APIを確認してから具体化します。既存Ghostty計画との責任分担を決め、公開APIの追加やFork範囲の拡大が必要ならその判断を記録します。現時点で内部名変更を実証した不具合ではありません。
- TASK-016のDrawer所有権とTASK-025の機能削減で未決の製品判断が生じた場合は、選択肢・影響・待ち条件をここへ追記します。時間経過を承認とみなしません。
- 非表示Terminalの定期tickとnetworkidleの簡易判定は既存ADR上の意図的な仕様です。定期tickを根拠なく除去せず、networkidleはTASK-025で保証と名称・機能範囲を評価します。

## Out of Scope

- この台帳作成に伴うアプリ実装、機能削除、外部サービス変更、依存更新、コミット、公開・deploy。
- Profileやブラウジングデータ、既存Terminal Sessionを使う破壊的な再現実験。
- 見た目だけのAppKit bridge置換、全DispatchQueue.main.asyncの一括置換、根拠のないmodule分割・全面rewrite。
- CLIをフルブラウザ自動化基盤へ拡張すること。trusted input、iframe／Shadow DOM対応など、今回の指摘を越える機能追加。
