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

- **Den**: すべての作業を含む、個人の作業環境全体。
- **Desk**: Boardを水平に並べる、大きな作業文脈。
- **Board**: 一つの作業文脈に集中するため、ユーザーが意図して作る作業面。
- **Sheet**: Board内に保持されるWeb画面。
- **Sheet Stack**: 一つのBoard内にある、Sheetの戻る・進むの連なり。

完全なプロダクト用語は[CONTEXT.md](./CONTEXT.md)を参照してください。

## 現在の機能

- 複数のDeskにBoardを空間的に配置。
- Den ModeからBoardの移動、サイズ変更、複製、保持、配置、復元、終了。
- OverviewでDeskを跨いだBoardの確認と再配置。
- ブラウザの戻る・進むに相当する履歴を、BoardごとのSheet Stackとして保持。
- アプリ再起動後にDeskとBoardのラベル、並び順、幅、フォーカス、Current SheetのURLを復元。
- Sheet間で共有される永続的なWebプロファイルにより、アプリ再起動後もログイン状態を維持。
- スクロール、リンクヒント、検索、Sheet Stack操作、URL操作に対応する、任意のファーストパーティ製Vim-style Sheet Navigation。

## キーボード操作

`Control` + `,` でDen Modeを切り替えます。Den ModeはCurrent Sheet内のキーボードフォーカスに関係なく、DeskとBoardのコマンドを受け取ります。Held Boardがある場合、`Escape`で元の位置へ戻します。それ以外ではSheet Inputへ戻ります。

Den Modeの全ショートカットは[docs/shortcuts.md](./docs/shortcuts.md)を参照してください。

Vim-style Sheet Navigationは、Den Modeと別の任意機能です。Current Sheet内のコンテンツを操作し、デフォルトでは無効です。対応コマンドは[docs/vim.md](./docs/vim.md)を参照してください。

## 現在の対応範囲

- macOS 26以降が必要です。
- 永続的なWebプロファイルは一つだけです。プロファイルの分離にはまだ対応していません。
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
- [docs/vim.md](./docs/vim.md): Vim-style Sheet Navigation
- [docs/poc.md](./docs/poc.md): PoCの受け入れ基準
- [docs/testing.md](./docs/testing.md): 自動テストと手動検証
- [docs/adr](./docs/adr): プロダクトとアーキテクチャの意思決定
