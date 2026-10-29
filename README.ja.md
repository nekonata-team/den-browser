[English](./README.md) | [日本語](./README.ja.md) | [Webサイト](https://den.nekonata.dev/)

# Den Browser

**Webとターミナル作業を、Niriのように。** — [den.nekonata.dev](https://den.nekonata.dev/)

Den Browserは、長時間のWeb作業とターミナル作業に使う、キーボード中心の空間ブラウザです。
調査、AIチャット、開発、執筆やドキュメント作業を永続する作業面に保持し、並行する作業をすぐ再開できます。

## インストール

Den BrowserにはmacOS 26以降が必要です。

```sh
brew install --cask nekonata-team/tap/den-browser
```

更新には `brew upgrade --cask den-browser` を実行します。

### エージェントスキル

Claude CodeやCursorなどのコーディングエージェント向けスキルをインストールします。

```sh
npx skills add nekonata-team/den-browser --skill den
```

Terminal Boardから、同梱の`den` CLIで隣接するWeb Boardを確認、操作できます。

```sh
den board list
den board web snapshot -i
den board web text
```

### Ghostty設定

Terminal Boardは、標準のXDG/macOS設定ファイルを読み込みます。
設定例:

```ini
theme = dark:Catppuccin Mocha,light:Catppuccin Latte
copy-on-select = clipboard
```

Denはテーマ名を同梱カタログから解決します。
詳細は[Ghosttyの設定リファレンス](https://ghostty.org/docs/config/reference)を参照してください。

## 作業モデル

- **Profile**: ログイン状態、サイトデータ、DenをほかのProfileから分離する
  Web上の識別単位。
- **Den**: 一つのProfileに属する作業環境全体。
- **Desk**: Boardを水平に並べる、大きな作業文脈。
- **Board**: Web Sheet、Terminal Session、Zellij Session、またはzmx Sessionを保持する、永続する作業面。
- **Sheet**: Boardが保持して表示する内容の単位。
  Webの内容やTerminal Sessionを扱う。

[Niri](https://github.com/niri-wm/niri)の空間的なウィンドウ管理から着想を得た、Web作業、閲覧履歴や状態復元に適した紙の作業空間モデルです。
プロダクト用語は[CONTEXT.md](./CONTEXT.md)を参照してください。

## Den Browserの特徴

- 複数のDeskにまたがる、永続的な空間配置。
- 一つのDeskに並べられるWeb Board、Terminal Board、Zellij Board、zmx Board。
- キーボード中心の移動とBoard操作。必要な操作はポインターにも対応。
- Profileごとに分離されたログイン状態とサイトデータ。再起動後のDen状態復元。
- DeskやBoardの文脈がまだ決まっていないWeb上の素材やTerminal Sessionを置く、Den全体のDrawer。
- Current Sheet内のコンテンツを操作する、任意のファーストパーティ製
  Vim-style Sheet Navigation。

キーボード操作は[docs/shortcuts.md](./docs/shortcuts.md)を参照してください。

## 開発

Den BrowserはSwiftUI、AppKitブリッジ、`WKWebView`、libghosttyで構成されたmacOSアプリです。
Terminal Boardは通常のmacOSユーザー権限で動作し、アプリはApp Sandboxを使用しません。

```sh
mise install
just build
just test
just check
```

タスク一覧は`just --list`で確認できます。

## ドキュメント

- [CONTEXT.md](./CONTEXT.md): プロダクト用語とドメインモデル
- [docs/shortcuts.md](./docs/shortcuts.md): キーボードとポインタ操作
- [docs/cli.md](./docs/cli.md): CLIリファレンスとエージェントスキル
- [docs/architecture.md](./docs/architecture.md): ソースの所有範囲とモジュール境界
- [docs/testing.md](./docs/testing.md): 自動テストと探索的検証
- [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md): 同梱ソフトウェアのライセンス

開発への参加方法は [AGENTS.md](./AGENTS.md) を参照してください。

## ライセンス

Den Browserの自作コードは、[Mozilla Public License, version 2.0](./LICENSE)で提供します。
Copyright (c) 2026 nekonata.
