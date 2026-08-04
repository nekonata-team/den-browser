[English](./README.md) | [日本語](./README.ja.md)

# Den Browser

**Web作業を、Niriのように。**

Webで並行作業する人のための、キーボードファーストな空間ブラウザ。

> **現在の状態:** 主要機能が動作する、開発継続中のmacOS向けPoCです。

Den Browserは、AIチャット、調査、開発、執筆、ドキュメント作業など、複数の文脈を長時間保つWeb作業のためのブラウザです。作業の文脈をタブ一覧に貯めるのではなく、永続する作業面として空間的に配置し、キーボードで移動・整理できます。

SafariやChromeなどの汎用ブラウザを置き換えるものではありません。日常的なブラウジングには普段のブラウザを使い、空間記憶と長く続く文脈が役立つ作業にDen Browserを併用します。

## インストール

Den BrowserにはmacOS 26以降が必要です。

```sh
brew tap nekonata-team/tap
brew install --cask den-browser
```

更新には`brew upgrade --cask den-browser`を使用します。

## Niriからの着想

Den Browserは、[Niri](https://github.com/niri-wm/niri)の空間的なウィンドウ管理をWeb作業に応用します。NiriのworkspaceはDesk、windowはBoardにゆるく対応します。完全な対応関係ではなく、Den BrowserはWeb作業、閲覧履歴、状態復元に適した紙の作業空間モデルを採用しています。

## 作業モデル

- **Profile**: 一つのDenを持ち、ログイン状態とサイトデータをほかから分離するWeb上の識別単位。
- **Den**: 一つのProfileに属する作業環境全体。
- **Desk**: Boardを水平に並べる、大きな作業文脈。
- **Desk Preset**: Deskの作成または内容の置換に使う、再利用可能な初期配置。
- **Board**: 一つの作業文脈に集中するため、ユーザーが意図して作る作業面。
- **Sheet**: Board内に保持されるWeb画面。
- **Sheet Stack**: 一つのBoard内にある、Sheetの戻る・進むの連なり。

完全なプロダクト用語は[CONTEXT.md](./CONTEXT.md)を参照してください。

## 現在の機能

- 複数のDeskにBoardを空間的に配置。
- HTTPまたはHTTPSリンクをCommandクリックし、現在のFocusを保ったまま隣の新しいBoardで開く。Shiftを加えると新しいBoardへFocusを移す。OptionクリックではCurrent Sheetを変えず、Drawerを開かずにリンクを保持する。
- Desk Switcher のDeskボタンをドラッグしてDeskを並べ替え。
- Exportメニューから、Desk内のCurrent Sheetへのリンクを読みやすいMarkdown一覧として保存またはクリップボードへコピー。
- 名前と色を持つProfileを作成し、Profileごとに一つのDenウィンドウと分離されたWebサイトデータを保持。
- タイトルバーで現在のProfileを確認し、右上のアイコン、Profileメニュー、`Control` + `Command` + `P`からProfileを開く・検索。
- `Command` + `Option` + 左右矢印で隣のBoardへ移動し、Shiftを加えて並べ替え。`Command` + `L`でFocused BoardのCurrent SheetをURLまたは検索語に置き換え、`Command` + `W`でFocused Boardを取り除く。`Shift` + `Command` + `W`でProfileウィンドウを閉じる。Den ModeではBoardの全操作が可能。ポインターでもSheet Stack操作、Board Removal、同じDesk内でのヘッダードラッグ、Boardヘッダーからのアクションメニューに対応。
- アプリ全体で使うDenとBoardの8つのショートカットを設定で変更できる。`Control` + `Tab`系でDeskを移動し、`Option` + `Command` + `Tab`で直前のDeskへ戻れる。ショートカットは個別または一括で初期値に戻せ、設定、Denメニュー、Den Mode中の`?`から確認できる。
- Appearance設定で、macOSのモーション設定への追従、Standard Motion、Reduced Motionを選択可能。全ProfileのSheetへ適用する50%〜200%のSheet Scaleも設定できる。また、フォーカスされたBoardの配置アライメント（常に中央配置、端に詰める、画面からはみ出た時のみ中央配置）を選択可能。
- Den Mode中に`z`でZen Viewを切り替え、ネイティブのタイトルバー、Desk Switcher、Profileコントロールを非表示にしてFocused Boardでの作業へ集中。`t`でFocused BoardのSheet NavigationをPause / Resume。
- Den Mode中に`/`でFocused Desk内のBoardをBoard LabelまたはCurrent Sheet URLから絞り込み、フォーカスを変えずに一致するBoardを選んでから確定。
- Den Modeで`w`に続けて`-`、`=`、または`1`〜`9`を押すかDenメニューを使い、Focused Desk内の全Boardを80ptずつ、または現在のウィンドウ幅へ指定数が収まるようリサイズ。
- 現在のアプリ起動中、`u`でRecently Removed Boardを復活。
- Open BoardパネルのRecentから、以前のURLまたは検索語を再利用。
- Profile所有のDen-level DrawerへWeb materialを保持し、Item数を確認しながらDen Modeの`/`でtitleまたはURLから絞り込み、一度に一つのライブPreviewを展開。展開中のPreviewを破棄すると、表示順で次のItemがあればそのPreviewを開き、末尾なら一つ前のItemを開く。後からBoardとして配置、または破棄。Den Modeで`a`を押すとFocused BoardのCurrent SheetをDrawerへ保持し、Sheet Navigation有効時にSheet Inputで`a`に続けてリンクヒントを入力すると、そのリンクを保持。Drawer内でもDen Modeを切り替え、Previewのライブ状態を終わらせずにDrawer Itemと展開中のPreviewの間でキーボード操作を移せる。ほかのアプリから開いたリンクは現在のDesk配置を変えずにDrawerへ入る。展開中のPreviewは現在のアプリ起動中、Drawerを閉じてもライブ状態を保ち、再起動後は最初にDrawerを開いたとき新しいライブruntimeで再表示。
- OverviewでDeskを跨いだBoardの確認と再配置。
- 空のDeskは即座に削除し、Boardを含むDeskは完全削除の確認後に削除。
- Focused DeskをProfile所有のPersonal Desk Presetとして保存し、キーボード中心のファジー検索でPresetを選択、プレビューしてから、新しいDeskを作成、またはコンテキストメニューやDen ModeのShift + `p`から現在のDeskの内容を置換。Deskの置換ではDeskの同一性と位置を維持し、Boardを作り直す。Preset自体の置換、削除はPicker内で操作。組み込みのEmpty、ChatGPT、Geminiをすぐ使える初期配置として提供。
- ブラウザの戻る・進むに相当する履歴を、BoardごとのSheet Stackとして保持。
- Current Sheetからのファイルダウンロード時に、サイト指定のファイル名を引き継いだmacOSの保存パネルを表示し、完了結果を通知。
- `s`でFocused Boardの表示中のCurrent Sheetを撮影し、Shift + `s`でFocused Desk内の全Boardをラベルと相対幅を保った一枚のPNGに結合。
- アプリ再起動後にDeskとBoardのラベル、並び順、幅、フォーカス、Current SheetのURLを復元し、Focused Boardをスクロールアニメーションなしで即座に表示。
- `http` / `https` のブラウザハンドラーとして登録し、ほかのアプリから開いたURLを現在のProfileでPreview可能なDrawer Itemとして保持。既定のブラウザにするかどうかはmacOS側で選択。
- Profile内のSheet間でログイン状態を維持しつつ、別Profileから分離。
- スクロール、リンクヒント、検索、Sheet Stack操作、URL操作に対応する、任意のファーストパーティ製Vim-style Sheet Navigation。

## キーボード操作

`Control` + `,` でDen Modeを切り替えます。`Command` + `L`でFocused BoardのCurrent SheetをURLまたは検索語に置き換え、Den Modeでは`e`でも同じ操作を行えます。Den ModeはCurrent Sheet内のキーボードフォーカスに関係なく、DeskとBoardのコマンドを受け取ります。`/`でFocused Desk内のBoardを絞り込み、`n`または`Space`でBoardを開き、`Tab`でDrawerを開き、`a`でCurrent SheetをDrawerへ保持し、`p`でFocused DeskをDesk Presetとして保存し、Shift + `p`でPresetからFocused Deskを置換します。`s`で表示中のCurrent Sheetを撮影し、Shift + `s`でFocused Deskを撮影します。`w`に続けて`-`または`=`を押すとFocused Desk内の全Boardを80ptずつ調整し、数字を押すと現在のウィンドウ幅に合わせてリサイズします。`x`または`d`でFocused Boardを取り除き、`u`でRecently Removed Boardを復活します。`?`でショートカット一覧を表示し、`z`でZen Viewを切り替え、`t`でFocused BoardのSheet NavigationをPause / Resumeします。`Escape`でSheet Inputへ戻ります。Sheet Navigation有効時は、Sheet Inputで`a`に続けてリンクヒントを入力すると、そのリンクをDrawerへ保持します。

全ショートカットは[docs/shortcuts.md](./docs/shortcuts.md)を参照してください。

Vim-style Sheet Navigationは、Den Modeと別の任意機能です。Current Sheet内のコンテンツを操作し、デフォルトでは無効です。対応コマンドは[docs/vim.md](./docs/vim.md)を参照してください。

## 現在の対応範囲

- macOS 26以降が必要です。
- ProfileとDenの状態はApplication Supportへローカル保存し、アプリ設定はすべてのProfileで共有します。
- 汎用ブラウザの全機能ではなく、長時間続くWebの並行作業に焦点を当てています。
- WebKit互換性、性能、アクセシビリティ、表示の検証を続けているPoCです。

現在の受け入れ基準と手動確認項目は[docs/poc.md](./docs/poc.md)を参照してください。

## 開発

Den BrowserはSwiftUI、AppKitブリッジ、`WKWebView`で構築されたmacOSアプリです。

```sh
mise install
just build
just test
just check
```

これらのコマンドはコード署名を無効にします。Lefthook はコミット前に `just format` と `just lint` を実行し、整形による変更を自動でステージします。プッシュ前には `just check` を実行します。

任意でNeovimのSourceKit-LSP連携を設定できます。

```sh
brew install xcode-build-server
just lsp-config
```

SourceKit-LSPがビルドログとインデックスを利用できるよう、先にXcodeでプロジェクトをビルドしてください。

## プロジェクトドキュメント

- [CONTEXT.md](./CONTEXT.md): プロダクト用語とドメインモデル
- [docs/architecture.md](./docs/architecture.md): ソース構成と依存境界
- [DESIGN.md](./DESIGN.md): 表示と操作のデザインルール
- [docs/shortcuts.md](./docs/shortcuts.md): Den Modeのキーボードコマンド
- [docs/desk-presets.md](./docs/desk-presets.md): Desk Presetの挙動と対応範囲
- [docs/screenshots.md](./docs/screenshots.md): Current SheetとDeskのスクリーンショット挙動
- [docs/vim.md](./docs/vim.md): Vim-style Sheet Navigation
- [docs/poc.md](./docs/poc.md): PoCの受け入れ基準
- [docs/testing.md](./docs/testing.md): 自動テストと手動検証
- [docs/releasing.md](./docs/releasing.md): 署名付きリリースとHomebrew Tapの手順
- [docs/adr](./docs/adr): プロダクトとアーキテクチャの意思決定
