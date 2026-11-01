# GoldBrain 🧠✨

**七个月的雄心、学习，以及一个尚未完成的金融智能工作台。**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain 是双胞胎兄弟 Bardiya 和 Armiya Alizadeh（Kabir）已停止开发的实验项目，将以波斯语为主的 Flutter 界面与 Python/FastAPI 后端相结合。保留源码，是为了让其他开发者理解已有工作、复现当前状态，并决定如何接着做。

共同创作者：**Bardiya Alizadeh (Kabir) · Farland_game** 和 **Armiya Alizadeh (Kabir) · ArmiyaFbix**。项目最新的“关于”页面和开发记录将两人的贡献标为同等。

据 Bardiya 介绍，他为此投入了大约七个月，起初几乎没有编程经验，主要通过实验、网络资料和 AI 辅助学习。最初的目标是开发 Windows/Android 产品，提供短期和长期市场预测，再加入 Wallex 自动交易，并且只使用用户自行划定的部分资金。由于基础设施需求、成本、复杂性和金融风险，他停止了对这一完整愿景的推进。这些是项目目标，并非已经完成或经过验证的能力。

> 大脑有宏伟计划，基础设施账单也有自己的计划。🧠🧾😅

## 保留的源码包含什么

- 自定义 Flutter 界面，包含 11 种主题、现有的 8 种界面语言、动画、图表、设置、自选列表、音频控制和“关于”页面。
- FastAPI 后端，包含标准化市场报价与历史数据、数据提供方溯源、时效性和质量检查、持久化概览数据，以及后台采集任务。
- 研究用途的预测引擎，包含特征计算、按时间顺序的评估与回测，以及证据记录；它与尚未完成的最终预测系统并不相同。
- 模拟交易 API；可见的投资组合界面和实盘交易尚未完成。
- 电子邮箱验证与密码重置流程、Argon2 密码处理、JWT 访问令牌、刷新令牌轮换，以及设备和会话控制。
- RSS 新闻、可选的 AI 文章翻译与摘要、权限受限且只读的聊天助手，以及覆盖六个国家的市场脉搏指标。
- 后端与 Flutter 测试源码、十个数据库迁移、配置示例、架构与 API 文档，以及历史进度和决策记录。

## 开发停在了哪里

- 计划中的 Phase 6 实时／自反馈预测系统尚未完成。其助手工具会明确报告不可用，而不会编造预测。
- Wallex 实盘自动交易和拟议的用户预算分配流程并未实现。交易所适配器只是一个模拟接口契约。
- 生产级数据协议、经独立验证的金融表现、公开部署加固，以及可靠的提供方访问，仍有待完成。
- 支付处理、完整的投资组合界面和一些可见设置尚未完成。订阅／权益模型并不等于已经建成的结账系统。
- 当前集成源码包含 Windows 和网页端框架；旧版 Android 框架单独保留。尚未验证当前版本的 Android 或网页端发行版能够正常运行。

## 接着做这个项目

请先阅读继续开发指南、全新克隆后的环境设置说明、当前状态矩阵和验证报告。历史文档保留了日期；其中的阶段标签、提供方价格和旧测试数量不能替代当前源码的实际情况。请配置自己的服务并使用全新数据库。本项目不提供私人账户数据库、API 凭据或 Android 签名身份。

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## 品牌素材与历史资料

包含提供的项目海报和标志。音频以单独的素材包分发，依据是创作者关于已获准再分发的声明；代码许可证不会自动涵盖这些音频。较早的源码快照是历史参考资料，不能作为当前应用中可随意互换的组件。

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="历史宣传海报：展示项目最初的构想，不代表经过验证的当前版本。"></a></p>

*历史宣传海报：展示项目最初的构想，不代表经过验证的当前版本。*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## 技术交接

详细技术指南使用英语，并保留了项目原有的英语／波斯语文档。这些作品集介绍与作品集其他部分一样，采用同一组 18 种文档语言；应用现有的 8 种界面语言是另一项功能。

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

复用代码或媒体前，请阅读仓库中的发布／许可记录，以及单独列出的第三方素材说明。

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
