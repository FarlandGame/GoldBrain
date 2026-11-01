# GoldBrain 🧠✨

**Сім місяців амбіцій, навчання й незавершене середовище фінансової аналітики.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain — припинений експериментальний проєкт братів-близнюків Bardiya та Armiya Alizadeh (Kabir). Він поєднує інтерфейс Flutter, розроблений насамперед для перської мови, з бекендом Python/FastAPI. Початковий код збережено, щоб інший розробник міг зрозуміти виконану роботу, відтворити поточний стан і вирішити, як її продовжити.

Співтворці: **Bardiya Alizadeh (Kabir) · Farland_game** та **Armiya Alizadeh (Kabir) · ArmiyaFbix**, зазначені на рівних у найновішому екрані «Про програму» та нотатках із розробки проєкту.

Bardiya розповідає про приблизно сім місяців роботи: починав із невеликим досвідом програмування й навчався через експерименти, онлайн-ресурси та допомогу ШІ. Початковим задумом був продукт для Windows/Android із коротко- й довгостроковими ринковими прогнозами, а згодом — автоматична торгівля на Wallex лише тією частиною коштів, яку обрав користувач. Він відмовився від реалізації всього цього задуму через вимоги до інфраструктури, витрати, складність і фінансовий ризик. Це були цілі, а не завершені чи підтверджені можливості.

> У мозку були великі плани. У рахунку за інфраструктуру — свої. 🧠🧾😅

## Що містить збережений початковий код

- Власний інтерфейс Flutter з 11 темами, 8 наявними мовами інтерфейсу, анімацією, графіками, налаштуваннями, списками спостереження, керуванням звуком і сторінкою «Про програму».
- Бекенд FastAPI з нормалізованими ринковими котируваннями та історією, відомостями про походження даних від постачальників, перевірками актуальності й якості, збереженими оглядовими даними та процесом збору.
- Дослідницький механізм прогнозування з обчислюваними ознаками, хронологічним оцінюванням/тестуванням на історичних даних і записами доказів; він відрізняється від незавершеного кінцевого прогнозувача.
- API симуляції торгівлі; видимий інтерфейс портфеля й торгівля реальними коштами не завершені.
- Процеси підтвердження електронної пошти й скидання пароля, паролі з Argon2, токени доступу JWT, ротація токенів оновлення та керування пристроями й сеансами.
- Новини RSS, необов'язкові переклади й підсумки статей за допомогою ШІ, обмежений чат-асистент із доступом лише для читання та огляд ринків шести країн.
- Початковий код тестів бекенду й Flutter, десять міграцій бази даних, приклади конфігурації, документи архітектури/API та історичні записи поступу й рішень.

## Де зупинилася робота

- Запланована для Фази 6 система прогнозування наживо зі зворотним зв'язком від власних результатів не завершена. Її інструмент асистента прямо повідомляє про недоступність, замість того щоб вигадувати прогноз.
- Автоматичну торгівлю реальними коштами на Wallex і запропонований процес розподілу бюджету користувача не реалізовано. Біржовий адаптер є імітаційним інтерфейсом.
- Угоди щодо даних для промислової експлуатації, незалежна перевірка фінансових результатів, посилення захисту для публічного розгортання та надійний доступ до постачальників залишаються відкритими завданнями.
- Обробка платежів, повний інтерфейс портфеля та деякі видимі налаштування не завершені. Модель підписок і прав доступу — це не завершена система оформлення покупок.
- Поточний інтегрований код містить каркаси для Windows і вебу; старіший каркас Android збережено окремо. Працездатність поточного випуску для Android чи вебу не перевірено.

## Продовжіть проєкт

Почніть із посібника з продовження роботи, налаштування свіжого клону, матриці поточного стану та звіту про перевірку. Історичні документи збережено з їхніми датами; їхні позначення фаз, ціни постачальників і старі кількості тестів не мають переваги над поточним кодом. Підготуйте власну конфігурацію сервісів і нову базу даних. Приватна база облікових записів, облікові дані API та ідентифікаційні дані підписання Android не надаються.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## Візуальна ідентичність та історичні матеріали

Додано надані постер і логотипи проєкту. Аудіо розповсюджується як окремий пакет ресурсів на підставі заяви творця про дозвіл на подальше розповсюдження; ліцензія коду не поширюється на нього автоматично. Старіші знімки початкового коду — це історичні довідкові матеріали, а не взаємозамінні компоненти поточної програми.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="Історичний рекламний постер: показує початковий задум проєкту, а не перевірений поточний випуск."></a></p>

*Історичний рекламний постер: показує початковий задум проєкту, а не перевірений поточний випуск.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## Технічне передавання проєкту

Докладні технічні посібники написано англійською; поруч збережено оригінальні документи проєкту англійською та перською. Ці представлення в портфоліо використовують ті самі 18 мов документації, що й решта портфоліо; 8 наявних мов інтерфейсу програми — окрема можливість.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

Перш ніж повторно використовувати код або медіа, прочитайте запис про публікацію/ліцензію репозиторію та окремі повідомлення про сторонні ресурси.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
