[English](./README.md) | [日本語](./README.ja.md)

# Den Browser

**Web作業を、Niriのように。**

Webで並行作業する人のための、キーボードファーストな空間ブラウザ。

> **現在の状態:** 主要機能が動作する、開発継続中のmacOS向けPoCです。

Den Browserは、AIチャット、調査、開発、執筆、ドキュメント作業など、複数の文脈を長時間保つWeb作業のためのブラウザです。作業の文脈をタブ一覧に貯めるのではなく、永続する作業面として空間的に配置し、キーボードで移動・整理できます。

SafariやChromeなどの汎用ブラウザを置き換えるものではありません。日常的なブラウジングには普段のブラウザを使い、空間記憶と長く続く文脈が役立つ作業にDen Browserを併用します。

## Niriからの着想

Den Browserは、[Niri](https://github.com/niri-wm/niri)の空間的なウィンドウ管理をWeb作業に応用します。NiriのworkspaceはDesk、windowはBoardにゆるく対応します。完全な対応関係ではなく、Den BrowserはWeb作業、閲覧履歴、状態復元に適した紙の作業空間モデルを採用しています。

## 作業モデル

- **Profile**: 一つのDenを持ち、ログイン状態とサイトデータをほかから分離するWeb上の識別単位。
- **Den**: 一つのProfileに属する作業環境全体。
- **Desk**: Boardを水平に並べる、大きな作業文脈。
- **Desk Template**: Desk作成時に使う、再利用可能な初期配置。
- **Board**: 一つの作業文脈に集中するため、ユーザーが意図して作る作業面。
- **Sheet**: Board内に保持されるWeb画面。
- **Sheet Stack**: 一つのBoard内にある、Sheetの戻る・進むの連なり。

完全なプロダクト用語は[CONTEXT.md](./CONTEXT.md)を参照してください。

## 現在の機能

- 複数のDeskにBoardを空間的に配置。
- 名前と色を持つProfileを作成し、Profileごとに一つのDenウィンドウと分離されたWebサイトデータを保持。
- タイトルバーで現在のProfileを確認し、右上のアイコン、Profileメニュー、`Control` + `Command` + `P`からProfileを開く・検索。
- `Command` + `Option` + 左右矢印で隣のBoardへ移動し、Shiftを加えて並べ替え。`Command` + `W`でFocused Boardを取り除き、`Shift` + `Command` + `W`でProfileウィンドウを閉じる。Den ModeではBoardの全操作が可能。ポインターでもSheet Stack操作、Board Removal、同じDesk内でのヘッダードラッグ、Boardヘッダーからのアクションメニューに対応。
- アプリ全体で使うDenとBoardの5つのショートカットを設定で変更し、個別または一括で初期値に戻せる。全ショートカットは設定、Denメニュー、Den Mode中の`?`から確認可能。
- Appearance設定で、macOSのモーション設定への追従、Standard Motion、Reduced Motionを選択可能。
- Den Mode中に`z`でZen Viewを切り替え、タイトルバーを残したままDesk SwitcherとProfileコントロールを非表示。
- Den Modeで`w`に続けて`1`〜`9`を押すかDenメニューを使い、現在のウィンドウ幅へ指定数が収まるようFocused Desk内の全Boardをリサイズ。
- 現在のアプリ起動中、`u`でRecently Removed Boardを復活。
- OverviewでDeskを跨いだBoardの確認と再配置。
- 空のDeskは即座に削除し、Boardを含むDeskは完全削除の確認後に削除。
- Focused DeskをProfile所有のPersonal Desk Templateとして保存し、新しいDeskの作成時はキーボード中心のファジー検索でTemplateを選択、プレビューしてからDesk Labelを入力。Templateの置換、削除に対応し、Den ModeではShift + `b`から管理画面を直接表示。組み込みのEmpty、ChatGPT、Geminiをすぐ使える初期配置として提供。
- ブラウザの戻る・進むに相当する履歴を、BoardごとのSheet Stackとして保持。
- アプリ再起動後にDeskとBoardのラベル、並び順、幅、フォーカス、Current SheetのURLを復元し、Focused Boardをスクロールアニメーションなしで即座に表示。
- Profile内のSheet間でログイン状態を維持しつつ、別Profileから分離。
- スクロール、リンクヒント、検索、Sheet Stack操作、URL操作に対応する、任意のファーストパーティ製Vim-style Sheet Navigation。

## キーボード操作

`Control` + `,` でDen Modeを切り替えます。Den ModeはCurrent Sheet内のキーボードフォーカスに関係なく、DeskとBoardのコマンドを受け取ります。`n`または`Space`でBoardを開き、`b`でFocused DeskをDesk Templateとして保存し、`w`に続けて数字を押すとFocused Desk内の全Boardを現在のウィンドウ幅に合わせてリサイズします。`x`または`d`でFocused Boardを取り除き、`u`でRecently Removed Boardを復活します。`?`でショートカット一覧を表示し、`z`でZen Viewを切り替えます。`Escape`でSheet Inputへ戻ります。

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
just build
just test
just check
```

これらのコマンドはコード署名を無効にし、ビルド出力を`.derived-data`に書き込みます。

## プロジェクトドキュメント

- [CONTEXT.md](./CONTEXT.md): プロダクト用語とドメインモデル
- [DESIGN.md](./DESIGN.md): 表示と操作のデザインルール
- [docs/shortcuts.md](./docs/shortcuts.md): Den Modeのキーボードコマンド
- [docs/desk-templates.md](./docs/desk-templates.md): Desk Templateの挙動と対応範囲
- [docs/vim.md](./docs/vim.md): Vim-style Sheet Navigation
- [docs/poc.md](./docs/poc.md): PoCの受け入れ基準
- [docs/testing.md](./docs/testing.md): 自動テストと手動検証
- [docs/adr](./docs/adr): プロダクトとアーキテクチャの意思決定
