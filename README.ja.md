[English](./README.md) | [日本語](./README.ja.md)

# Den Browser

**Webとターミナル作業を、Niriのように。**

Den Browserは、長時間続くWeb・ターミナル作業のためのキーボードファーストな空間
ブラウザです。増え続けるタブやターミナルウィンドウの代わりに、並行する作業を永続する
作業面として保持し、調査、AIチャット、開発、執筆、ドキュメント作業を
後からすぐ再開できます。

> **現在の状態:** 主要機能が動作する、開発継続中のmacOS向けPoCです。

SafariやChromeなどの汎用ブラウザを置き換えるものではありません。日常の
ブラウジングには普段のブラウザを使い、空間記憶と長く続く文脈が役立つ
作業にDen Browserを併用します。

## インストール

Den BrowserにはmacOS 26以降が必要です。

```sh
brew tap nekonata-team/tap
brew install --cask den-browser
```

更新には `brew upgrade --cask den-browser` を使用します。

## 作業モデル

- **Profile**: ログイン状態、サイトデータ、DenをほかのProfileから分離する
  Web上の識別単位。
- **Den**: 一つのProfileに属する作業環境全体。
- **Desk**: Boardを水平に並べる、大きな作業文脈。
- **Board**: Web Sheet、Terminal Session、Zellij Session、またはzmx Sessionを保持する、永続する作業面。
- **Sheet**: Board内に保持されるWeb画面。

Den Browserは、[Niri](https://github.com/niri-wm/niri)の空間的なウィンドウ
管理から着想を得ています。Web作業、閲覧履歴、状態復元に適した紙の作業
空間モデルです。完全なプロダクト用語は[CONTEXT.md](./CONTEXT.md)を参照して
ください。

## Den Browserの特徴

- 複数のDeskにまたがる、永続的な空間配置。
- 一つのDeskに並べられるWeb Board、Terminal Board、Zellij Board、zmx Board。
- キーボード中心の移動とBoard操作。必要な操作はポインターにも対応。
- Profileごとに分離されたログイン状態とサイトデータ。再起動後のDen状態復元。
- DeskやBoardの文脈がまだ決まっていないWeb上の素材を置く、Den全体のDrawer。
- Current Sheet内のコンテンツを操作する、任意のファーストパーティ製
  Vim-style Sheet Navigation。

詳しいキーボード操作は[docs/shortcuts.md](./docs/shortcuts.md)、現在の受け入れ
基準と手動確認項目は[docs/poc.md](./docs/poc.md)を参照してください。

## 開発

Den BrowserはSwiftUI、AppKitブリッジ、`WKWebView`、libghosttyで構成されたmacOSアプリです。
Terminal Boardは通常のmacOSユーザー権限で動作し、アプリはApp Sandboxを使用しません。

```sh
mise install
just build
just test
just check
```

これらのコマンドはコード署名を無効にします。利用できるタスクは
`just --list`で確認できます。

## ドキュメント

- [CONTEXT.md](./CONTEXT.md): プロダクト用語とドメインモデル
- [DESIGN.md](./DESIGN.md): ビジュアルとインタラクションのルール
- [docs/shortcuts.md](./docs/shortcuts.md): Den Modeのキーボード操作
- [docs/desk-presets.md](./docs/desk-presets.md): Desk Presetの挙動
- [docs/vim.md](./docs/vim.md): Vim-style Sheet Navigation
- [docs/architecture.md](./docs/architecture.md): ソース構成と境界
- [docs/testing.md](./docs/testing.md): 自動テストと手動検証
- [docs/releasing.md](./docs/releasing.md): 署名付きリリース手順
- [docs/adr](./docs/adr): プロダクトとアーキテクチャの意思決定
- [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md): 同梱ソフトウェアのライセンス

## ライセンス

Den Browserの自作コードは、[Mozilla Public License, version 2.0](./LICENSE)で提供します。
Copyright (c) 2026 nekonata.
