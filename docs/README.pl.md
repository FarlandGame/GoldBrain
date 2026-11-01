# GoldBrain 🧠✨

**Siedem miesięcy ambicji, nauki i niedokończone środowisko analizy rynków finansowych.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain to porzucony projekt eksperymentalny braci bliźniaków Bardiya i Armiya Alizadeh (Kabir). Łączy interfejs Flutter zaprojektowany przede wszystkim z myślą o języku perskim z backendem Python/FastAPI. Kod źródłowy zachowano, aby inny programista mógł zrozumieć dotychczasową pracę, odtworzyć obecny stan i zdecydować, jak ją kontynuować.

Współtwórcy: **Bardiya Alizadeh (Kabir) · Farland_game** oraz **Armiya Alizadeh (Kabir) · ArmiyaFbix**, wymienieni na równych prawach na najnowszym ekranie informacji o programie i w notatkach z rozwoju projektu.

Bardiya opowiada o około siedmiu miesiącach pracy, rozpoczętej z niewielkim doświadczeniem programistycznym i kontynuowanej poprzez eksperymenty, materiały internetowe i pomoc AI. Początkową ambicją był produkt na Windows/Android z krótko- i długoterminowymi prognozami rynkowymi, a następnie automatyczny handel na Wallex z wykorzystaniem wyłącznie wybranej przez użytkownika części jego środków. Zrezygnował z realizacji tej pełnej wizji ze względu na wymagania infrastrukturalne, koszty, złożoność i ryzyko finansowe. Były to cele, a nie ukończone lub zweryfikowane możliwości.

> Mózg miał wielkie plany. Rachunek za infrastrukturę też miał swoje. 🧠🧾😅

## Co zawiera zachowany kod źródłowy

- Autorski interfejs Flutter z 11 motywami, 8 istniejącymi językami interfejsu, animacjami, wykresami, ustawieniami, listami obserwowanych instrumentów, sterowaniem dźwiękiem i stroną informacji o programie.
- Backend FastAPI ze znormalizowanymi notowaniami i historią rynku, informacjami o pochodzeniu danych od dostawców, kontrolami aktualności i jakości, trwale zapisanymi danymi przeglądowymi oraz procesem zbierania danych.
- Eksperymentalny silnik prognozowania z wyliczanymi cechami, oceną chronologiczną/testami na danych historycznych i zapisami dowodów; jest odrębny od niedokończonego docelowego predyktora.
- API symulowanego handlu; widoczny interfejs portfela i handel prawdziwymi pieniędzmi nie są ukończone.
- Procesy weryfikacji adresu e-mail i resetowania hasła, hasła z Argon2, tokeny dostępu JWT, rotacja tokenów odświeżania oraz zarządzanie urządzeniami i sesjami.
- Wiadomości RSS, opcjonalne tłumaczenia i podsumowania artykułów przez AI, ograniczony asystent czatu z dostępem tylko do odczytu oraz przegląd rynków sześciu krajów.
- Kod źródłowy testów backendu i Fluttera, dziesięć migracji bazy danych, przykłady konfiguracji, dokumenty architektury/API oraz historyczne zapisy postępów i decyzji.

## Na czym zatrzymała się praca

- Planowany w Fazie 6 system prognozowania na żywo ze sprzężeniem zwrotnym z własnych wyników jest niedokończony. Jego narzędzie dla asystenta wyraźnie zgłasza niedostępność, zamiast wymyślać prognozę.
- Automatyczny handel prawdziwymi pieniędzmi na Wallex i proponowany proces przydzielania budżetu użytkownika nie zostały zaimplementowane. Adapter giełdy jest interfejsem symulowanym.
- Umowy dotyczące danych do zastosowania produkcyjnego, niezależna walidacja wyników finansowych, zabezpieczenia publicznego wdrożenia i niezawodny dostęp do dostawców pozostają do zrobienia.
- Obsługa płatności, kompletny interfejs portfela i niektóre widoczne ustawienia są niedokończone. Model subskrypcji i uprawnień dostępu nie jest ukończonym systemem zakupów.
- Obecny zintegrowany kod zawiera szkielety dla Windows i przeglądarki; starszy szkielet Androida zachowano osobno. Nie zweryfikowano działającego aktualnego wydania na Androida ani do przeglądarki.

## Podejmij dalszą pracę nad projektem

Zacznij od przewodnika kontynuacji, konfiguracji świeżego klonu, macierzy obecnego stanu i raportu weryfikacji. Dokumenty historyczne zachowano z ich datami; użyte w nich oznaczenia faz, ceny dostawców i dawne liczby testów nie są nadrzędne wobec aktualnego kodu. Przygotuj własną konfigurację usług i nową bazę danych. Nie udostępniono prywatnej bazy kont, danych uwierzytelniających API ani tożsamości do podpisywania aplikacji Android.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## Identyfikacja wizualna i materiały historyczne

Dołączono dostarczony plakat projektu i logotypy. Dźwięki są rozpowszechniane jako osobny pakiet zasobów na podstawie oświadczenia twórcy, że redystrybucja jest dozwolona; nie są automatycznie objęte licencją kodu. Starsze migawki kodu źródłowego stanowią historyczny materiał referencyjny, a nie wymienne komponenty obecnej aplikacji.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="Historyczny plakat promocyjny: przedstawia pierwotną wizję projektu, a nie zweryfikowane aktualne wydanie."></a></p>

*Historyczny plakat promocyjny: przedstawia pierwotną wizję projektu, a nie zweryfikowane aktualne wydanie.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## Przekazanie techniczne

Szczegółowe przewodniki techniczne są po angielsku, obok zachowanych oryginalnych dokumentów projektu po angielsku i persku. Te opisy portfolio używają tych samych 18 języków dokumentacji co reszta portfolio; 8 istniejących języków interfejsu aplikacji to osobna funkcja.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

Przed ponownym wykorzystaniem kodu lub mediów przeczytaj zapis publikacji/licencji repozytorium i osobne informacje dotyczące zasobów osób trzecich.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
