# init-nodejs-nextjs
Next.js を使った開発の入口まで自動で構築できる shell です。

## 使用前の準備
- docker をインストールしていること
- docker-compose をインストールしていること
- インターネットに接続できること

## 使用方法
1. bash / zsh を実行できるターミナルで `$ sh init-nodejs-nextjs.sh {プロジェクト名}` を実行する
2. 開発サーバが起動するまで (ターミナルに http://localhost:3000 と表示されるまで) 待って、 Web ブラウザで https://localhost にアクセスする
以上

## アプリの構成
- next.js (OAuth, PWA, Typescript のライブラリ入り)
- Let's encrypt で SSL 接続可

## 起動後の設定 (参考)
- OAuth に対応している認証サーバを用意し、設定ファイルを更新する Ref. https://next-auth.js.org/providers/slack
- PWA のマニフェストファイルを作成して配置する Ref. https://zenn.dev/tns_00/articles/next-pwa-install
- データベースを使う場合は、生成された docker-compose.yaml を更新してコンテナを再構築する
