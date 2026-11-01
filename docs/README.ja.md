# GoldBrain 🧠✨

**7か月の挑戦と学びから生まれた、未完成の金融インテリジェンス・ワークスペース。**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain は、双子の兄弟 Bardiya と Armiya Alizadeh（Kabir）による、開発を中止した実験的なプロジェクトです。ペルシャ語を中心に設計した Flutter インターフェースと、Python／FastAPI のバックエンドを組み合わせています。別の開発者が取り組みを理解し、現在の状態を再現して、今後の開発方針を決められるよう、ソースコードを保存しています。

共同制作者：**Bardiya Alizadeh (Kabir) · Farland_game** と **Armiya Alizadeh (Kabir) · ArmiyaFbix**。プロジェクトの最新の About 画面と開発記録では、両者が対等な共同制作者として記載されています。

Bardiya によると、プログラミング経験が少ない状態から始め、試行錯誤、オンライン資料、AI の支援を通じて学びながら、約7か月取り組みました。当初の構想は、短期・長期の市場予測を備えた Windows／Android 製品を作り、さらに利用者が指定した資金の一部だけを使って Wallex で自動売買することでした。しかし、必要なインフラ、費用、複雑さ、金銭的なリスクを理由に、その構想全体を追い求めることをやめました。これらは目標であり、完成済み、または検証済みの機能ではありません。

> 頭脳には壮大な計画がありました。インフラの請求書にも、独自の計画があったようです。🧠🧾😅

## 保存されたソースコードに含まれるもの

- 11種類のテーマ、既存の8つのインターフェース言語、アニメーション、チャート、設定、ウォッチリスト、音声コントロール、About ページを備えた独自の Flutter インターフェース。
- 正規化された市場価格・履歴、提供元の情報、鮮度と品質の検査、永続化した概要データ、収集ワーカーを備えた FastAPI バックエンド。
- 特徴量、時系列順の評価・バックテスト、根拠の記録を備えた研究用予測エンジン。未完成の最終予測システムとは別のものです。
- 模擬取引（ペーパートレーディング）の API。画面上のポートフォリオ UI と実際の資金による取引は完成していません。
- メール確認・パスワード再設定のフロー、Argon2 によるパスワードハッシュ、JWT アクセストークン、リフレッシュトークンのローテーション、端末・セッション管理。
- RSS ニュース、任意の AI 記事翻訳・要約、機能を限定した読み取り専用チャットアシスタント、6か国の市場動向表示。
- バックエンドと Flutter のテストコード、10件のデータベースマイグレーション、設定例、アーキテクチャ・API 文書、過去の進捗・意思決定記録。

## 開発が止まった地点

- Phase 6 で予定していたリアルタイム予測・自己フィードバックシステムは未完成です。対応するアシスタントツールは、予測を捏造せず、利用できないことを明示します。
- 実際の資金を使う Wallex の自動売買と、提案されていた利用者の予算配分フローは未実装です。取引所アダプターはモックの契約定義です。
- 本番利用に適したデータ契約、独立した金融パフォーマンス検証、一般公開に向けた運用強化、安定したプロバイダー接続は、今後の課題です。
- 決済処理、完全なポートフォリオ UI、一部の画面上の設定は未完成です。サブスクリプションや利用権限のモデルがあることは、購入・決済システムの完成を意味しません。
- 現在の統合ソースには Windows と Web のひな形があります。古い Android のひな形は別途保存されています。現在の Android 版や Web 版が正常に動作するリリースは確認されていません。

## プロジェクトを引き継ぐには

継続開発ガイド、新規クローンからのセットアップ手順、現状の機能一覧、検証レポートから始めてください。過去の文書は日付付きで保存していますが、そこにあるフェーズ名、プロバイダー料金、古いテスト件数よりも、現在のソースコードが優先されます。サービス設定はご自身で用意し、新しいデータベースを使用してください。個人のアカウントデータベース、API 認証情報、Android の署名情報は提供していません。

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## ブランド素材と過去の資料

提供されたプロジェクトのポスターとロゴを収録しています。音声は、再配布が許可されているという制作者の申告に基づき、別のアセットパックとして配布しています。コードのライセンスが自動的に音声にも適用されるわけではありません。古いソースのスナップショットは歴史的な参考資料であり、現在のアプリの部品とそのまま置き換えられるものではありません。

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="過去のプロモーションポスターです。当初の構想を示すもので、現在の動作確認済みリリースを表すものではありません。"></a></p>

*過去のプロモーションポスターです。当初の構想を示すもので、現在の動作確認済みリリースを表すものではありません。*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## 技術的な引き継ぎ

詳細な技術ガイドは英語で、保存した元の英語・ペルシャ語のプロジェクト文書とともに提供しています。このポートフォリオ紹介は、ほかの作品紹介と同じ18言語に対応しています。アプリに既存の8つのインターフェース言語があることとは別です。

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

コードやメディアを再利用する前に、リポジトリの公開・ライセンス記録と、サードパーティー素材に関する個別の通知をお読みください。

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
