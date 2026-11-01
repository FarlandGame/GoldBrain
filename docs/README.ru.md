# GoldBrain 🧠✨

**Семь месяцев амбиций, обучения и работы над незавершённой системой финансовой аналитики.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain — экспериментальный проект братьев-близнецов Bardiya и Armiya Alizadeh (Kabir), работа над которым прекращена. Он объединяет интерфейс на Flutter, ориентированный прежде всего на персидский язык, и серверную часть на Python/FastAPI. Исходный код сохранён, чтобы другой разработчик мог разобраться в проделанной работе, воспроизвести текущее состояние и решить, как продолжить проект.

Соавторы: **Bardiya Alizadeh (Kabir) · Farland_game** и **Armiya Alizadeh (Kabir) · ArmiyaFbix**. В последней версии экрана «О программе» и в записях о разработке их вклад указан как равный.

По словам Bardiya, работа заняла около семи месяцев: он начинал почти без опыта программирования и учился через эксперименты, материалы в интернете и помощь ИИ. Изначально он хотел создать продукт для Windows и Android с краткосрочными и долгосрочными прогнозами рынка, а затем добавить автоматическую торговлю на Wallex с использованием только той части средств, которую выделит пользователь. Он отказался от реализации всего замысла из-за требований к инфраструктуре, затрат, сложности и финансового риска. Это были цели, а не завершённые или проверенные возможности.

> У мозга были большие планы. У счёта за инфраструктуру — свои. 🧠🧾😅

## Что содержится в сохранённом исходном коде

- Собственный интерфейс на Flutter с 11 темами, 8 существующими языками интерфейса, анимацией, графиками, настройками, списками наблюдения, управлением звуком и страницей «О программе».
- Серверная часть на FastAPI с нормализованными котировками и историей рынка, сведениями об источниках данных, проверками актуальности и качества, сохранёнными обзорными данными и фоновым сборщиком.
- Исследовательский механизм прогнозирования с расчётом признаков, хронологической оценкой и тестированием на исторических данных, а также записями подтверждающих данных; это не незавершённая окончательная система прогнозирования.
- API для учебной торговли без реальных денег; видимый интерфейс портфеля и торговля реальными средствами не завершены.
- Подтверждение электронной почты и сброс пароля, пароли с Argon2, JWT-токены доступа, ротация refresh-токенов и управление устройствами и сеансами.
- Новости из RSS, необязательные перевод и краткое изложение статей с помощью ИИ, чат-помощник с ограниченными полномочиями только на чтение и индикатор рыночного пульса по шести странам.
- Исходный код тестов серверной части и Flutter, десять миграций базы данных, примеры конфигурации, документы по архитектуре и API, а также исторические записи о ходе работы и принятых решениях.

## На чём остановилась работа

- Запланированная на Phase 6 система прогнозирования в реальном времени с обратной связью остаётся незавершённой. Соответствующий инструмент помощника явно сообщает о недоступности, а не выдумывает прогноз.
- Автоматическая торговля реальными средствами на Wallex и предложенный процесс выделения пользовательского бюджета не реализованы. Адаптер биржи — имитация интерфейсного контракта.
- Соглашения о данных для промышленного использования, независимая проверка финансовых результатов, подготовка публичного развёртывания и надёжный доступ к провайдерам остаются открытыми задачами.
- Обработка платежей, полный интерфейс портфеля и некоторые видимые настройки не завершены. Модель подписок и прав доступа не означает наличия готовой системы оплаты.
- В текущем интегрированном исходном коде есть каркасы для Windows и веба; старый каркас Android сохранён отдельно. Работоспособная актуальная версия для Android или веба не проверена.

## Продолжить проект

Начните с руководства по продолжению разработки, инструкции по настройке свежего клона, матрицы текущего состояния и отчёта о проверке. Исторические документы сохранены с датами; их обозначения этапов, цены провайдеров и старые количества тестов не имеют приоритета над текущим исходным кодом. Настройте собственные сервисы и создайте новую базу данных. Частная база учётных записей, API-ключи и идентификаторы подписи Android не предоставляются.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## Фирменные материалы и история проекта

Приложены предоставленные постер и логотипы проекта. Аудио распространяется отдельным набором ресурсов на основании заявления автора о наличии разрешения на распространение; лицензия на код не распространяется на него автоматически. Старые снимки исходного кода служат историческими справочными материалами, а не взаимозаменяемыми компонентами текущего приложения.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="Исторический рекламный постер: показывает первоначальный замысел проекта, а не проверенный текущий выпуск."></a></p>

*Исторический рекламный постер: показывает первоначальный замысел проекта, а не проверенный текущий выпуск.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## Передача технической информации

Подробные технические руководства написаны на английском языке; рядом сохранены оригинальные документы проекта на английском и персидском. Эти описания для портфолио доступны на тех же 18 языках документации, что и остальное портфолио; существующие 8 языков интерфейса приложения — отдельная возможность.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

Перед повторным использованием кода или медиа прочитайте сведения о публикации и лицензировании в репозитории и отдельные уведомления о сторонних ресурсах.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
