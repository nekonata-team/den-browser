---
layout: ../../layouts/LegalLayout.astro
title: プライバシーポリシー
date: 2026年8月22日
---

Den Browserは、**ローカルファーストかつプライバシー重視**の設計思想で開発されています。ユーザーのブラウジング履歴やセッションデータは、常にユーザー自身の制御下にあるべきだと考えています。

## 1. 情報の収集および外部送信について

Den Browserは、個人情報やテレメトリを収集せず、閲覧履歴、アクセスしたURL、ターミナルで実行したコマンドなどの利用データを、Den Browserのサーバーや第三者サービスへ送信しません。

Den Browserのローカルデータは、macOSが管理する複数の保存先に分かれて保存されます：
* ProfileとDenの状態（Profile設定、Desk・Board・Drawerの配置、Current SheetのURL、Terminal Boardの作業ディレクトリ、Zellij/zmxセッション名、Personal Desk Preset、Recentなど）は、`~/Library/Application Support/Den Browser/Profiles/` 以下のJSONに保存されます。このディレクトリには `profile-index.json` と、Profileごとの `<profile-id>.json` が含まれます。
* ショートカット、外観、Sheet Navigation、コンテンツブロック、ターミナル実行ファイルのパス、Essentialsなどのアプリ全体の設定は、アプリケーション識別子 `dev.nekonata.denbrowser` のmacOS `UserDefaults` に保存されます。
* Cookie、キャッシュ、ローカルストレージ、保存されたログイン情報、WebExtensionのデータは、Profileごとの永続 `WKWebsiteDataStore` が所有し、WebKitが管理します。ProfileのJSONには保存されません。

実行中の `WKWebView`、ターミナルプロセス、ターミナル画面、スクロールバック、一時的な復元履歴はDen Browserによって永続化されません。シェル、Zellij、zmxは、ユーザーの設定に応じて独自のファイルや履歴を保存する場合があります。これらはDen Browserの管理対象外です。

## 2. WebKit およびブラウザデータについて

Den Browserは、Webページの読み込みにmacOS標準の **`WKWebView`（WebKit）** レンダリングエンジンを使用しています。
* Profileごとに独立した `WKWebsiteDataStore` インスタンスを用いてデータを分離しています。あるProfileのデータが他のProfileに漏洩したり、アクセスされたりすることはありません。
* 開発元が、ブラウザ内で使用されるパスワードや認証資格情報にアクセスしたり、保存したりすることはありません。

## 3. コンテンツブロック機能（uBlock Origin Lite）について

Den Browserは、**uBlock Origin Lite (uBOL)** を内蔵コンテンツブロッカーとして搭載しています。
* **オプトイン（初期状態オフ）**: コンテンツブロックは初期状態では無効化されており、設定画面でユーザーが明示的に有効にした場合のみ動作します。
* 有効化時も、広告やトラッカーの遮断は静的ルールに基づきユーザーの端末内で完全に完結して実行されます。
* 閲覧履歴、アクセスしたURL、Webページの内容が外部サーバーへ送信されることは一切ありません。

## 4. ターミナルセッションについて

Terminal Boardは、通常のユーザー権限のもとでMacローカル上で直接動作します。Ghosttyによる描画やシェルプロセスの実行において、外部へのログ送信やテレメトリ通信は一切行われません。

## 5. サードパーティウェブサイトについて

Den Browserを使用して第三者のウェブサイトにアクセスした際、それらのウェブサイトは独自のプライバシーポリシーに従ってクッキーやIPアドレス等の情報を収集する場合があります。

## 6. 本ポリシーの改定について

本プライバシーポリシーは、アプリのアップデート等に伴い必要に応じて改定される場合があります。改定されたポリシーは本ページにて公開され、常にローカルファーストの原則を維持します。

## 7. お問い合わせ

本ポリシーまたは Den Browser のプライバシーに関するお問い合わせは、[GitHub リポジトリ](https://github.com/nekonata-team/den-browser)までお寄せください。

## 8. 改定履歴

* **2026年8月22日**: uBlock Origin Lite の連携がオプトインである旨を明記し、ターミナルセッションおよびローカル保存データの対象範囲を明確化。
* **2026年7月20日**: プライバシーポリシー初版制定。
