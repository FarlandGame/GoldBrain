# GoldBrain 🧠✨

**七個月的雄心、學習，以及一個尚未完成的金融智慧工作台。**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain 是雙胞胎兄弟 Bardiya 和 Armiya Alizadeh（Kabir）已停止開發的實驗專案，結合以波斯語為主的 Flutter 介面與 Python/FastAPI 後端。保留原始碼，是為了讓其他開發者理解已有成果、重現目前狀態，並決定如何繼續。

共同創作者：**Bardiya Alizadeh (Kabir) · Farland_game** 和 **Armiya Alizadeh (Kabir) · ArmiyaFbix**。專案最新的「關於」頁面和開發紀錄將兩人的貢獻標為同等。

據 Bardiya 所述，他為此投入了大約七個月，起初幾乎沒有程式設計經驗，主要透過實驗、網路資料和 AI 輔助學習。最初的目標是開發 Windows/Android 產品，提供短期和長期市場預測，再加入 Wallex 自動交易，而且只使用使用者自行劃定的部分資金。由於基礎設施需求、成本、複雜性和金融風險，他停止推進這個完整願景。這些是專案目標，並非已完成或經過驗證的能力。

> 大腦有宏偉計畫，基礎設施帳單也有自己的計畫。🧠🧾😅

## 保留的原始碼包含什麼

- 自訂 Flutter 介面，包含 11 種佈景主題、現有的 8 種介面語言、動畫、圖表、設定、自選清單、音訊控制和「關於」頁面。
- FastAPI 後端，包含標準化市場報價與歷史資料、資料提供者溯源、時效性和品質檢查、持久化概覽資料，以及背景蒐集工作。
- 研究用途的預測引擎，包含特徵計算、依時間順序的評估與回測，以及佐證紀錄；它與尚未完成的最終預測系統並不相同。
- 模擬交易 API；可見的投資組合介面和實盤交易尚未完成。
- 電子郵件驗證與密碼重設流程、Argon2 密碼處理、JWT 存取權杖、更新權杖輪替，以及裝置和工作階段控制。
- RSS 新聞、選用的 AI 文章翻譯與摘要、權限受限且唯讀的聊天助理，以及涵蓋六個國家的市場脈動指標。
- 後端與 Flutter 測試原始碼、十個資料庫遷移、設定範例、架構與 API 文件，以及歷史進度和決策紀錄。

## 開發停在了哪裡

- 規劃中的 Phase 6 即時／自我回饋預測系統尚未完成。其助理工具會明確回報無法使用，而不會編造預測。
- Wallex 實盤自動交易和提議中的使用者預算分配流程並未實作。交易所配接器僅是模擬的介面契約。
- 正式營運所需的資料協議、經獨立驗證的金融表現、公開部署強化，以及可靠的提供者存取，仍待完成。
- 付款處理、完整的投資組合介面和一些可見設定尚未完成。訂閱／使用權益模型並不等於已建成的結帳系統。
- 目前整合的原始碼包含 Windows 和網頁端框架；舊版 Android 框架另行保留。尚未驗證目前版本的 Android 或網頁端發行版能夠正常運作。

## 接續這個專案

請先閱讀接續開發指南、全新複製後的環境設定說明、目前狀態矩陣和驗證報告。歷史文件保留了日期；其中的階段標籤、提供者價格和舊測試數量不能取代目前原始碼的實際情況。請設定自己的服務並使用全新資料庫。本專案不提供私人帳戶資料庫、API 憑證或 Android 簽署身分。

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## 品牌素材與歷史資料

包含提供的專案海報和標誌。音訊以獨立素材包散布，依據是創作者關於已獲准再散布的聲明；程式碼授權不會自動涵蓋這些音訊。較早的原始碼快照是歷史參考資料，不能視為目前應用程式中可以任意互換的元件。

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="歷史宣傳海報：展示專案最初的構想，不代表經過驗證的目前版本。"></a></p>

*歷史宣傳海報：展示專案最初的構想，不代表經過驗證的目前版本。*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## 技術交接

詳細技術指南使用英語，並保留了專案原有的英語／波斯語文件。這些作品集介紹與作品集其他部分一樣，採用同一組 18 種文件語言；應用程式現有的 8 種介面語言是另一項功能。

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

重複使用程式碼或媒體前，請閱讀儲存庫中的發布／授權紀錄，以及另列的第三方素材聲明。

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
