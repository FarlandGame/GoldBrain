# GoldBrain 🧠✨

**Sieben Monate voller Ehrgeiz und Lernen – und eine unvollendete Arbeitsumgebung für Finanzanalysen.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain ist ein eingestelltes experimentelles Projekt der Zwillingsbrüder Bardiya und Armiya Alizadeh (Kabir). Es verbindet eine vorrangig auf Persisch ausgelegte Flutter-Oberfläche mit einem Python/FastAPI-Backend. Der Quellcode bleibt erhalten, damit andere Entwickler die Arbeit nachvollziehen, den aktuellen Stand reproduzieren und über eine Fortsetzung entscheiden können.

Gemeinsame Urheber: **Bardiya Alizadeh (Kabir) · Farland_game** und **Armiya Alizadeh (Kabir) · ArmiyaFbix**. Im neuesten Info-Bildschirm und in den Entwicklungsnotizen des Projekts werden beide gleichberechtigt genannt.

Bardiya berichtet von ungefähr sieben Monaten Arbeit. Er begann mit wenig Programmiererfahrung und lernte durch Experimente, Online-Material und KI-Unterstützung. Ursprünglich sollte ein Produkt für Windows und Android entstehen, mit kurz- und langfristigen Marktprognosen und anschließend automatischem Handel auf Wallex, der nur einen vom Nutzer ausgewählten Teil seines Guthabens einsetzt. Wegen der nötigen Infrastruktur, der Kosten, der Komplexität und des finanziellen Risikos verfolgte er diese vollständige Vision nicht weiter. Das waren Ziele, keine fertiggestellten oder validierten Fähigkeiten.

> Das Gehirn hatte große Pläne. Die Infrastrukturrechnung hatte ihre ganz eigenen. 🧠🧾😅

## Was der erhaltene Quellcode enthält

- Eine eigene Flutter-Oberfläche mit 11 Designs, 8 vorhandenen Oberflächensprachen, Animationen, Diagrammen, Einstellungen, Watchlists, Audiosteuerung und einer Infoseite.
- Ein FastAPI-Backend mit normalisierten Marktkursen und historischen Daten, Herkunftsangaben zu den Anbietern, Aktualitäts- und Qualitätsprüfungen, gespeicherten Übersichtsdaten und einem Erfassungsworker.
- Eine Forschungsengine für Prognosen mit Merkmalen, chronologischer Auswertung und Backtesting sowie Belegdatensätzen; sie ist vom unvollendeten endgültigen Prognosesystem zu unterscheiden.
- APIs für simulierten Handel (Paper Trading); die sichtbare Portfolio-Oberfläche und der Handel mit echtem Geld sind nicht fertiggestellt.
- Abläufe zur E-Mail-Bestätigung und zum Zurücksetzen von Passwörtern, Argon2-Passworthashes, JWT-Zugriffstoken, Rotation von Aktualisierungstoken sowie Geräte- und Sitzungsverwaltung.
- RSS-Nachrichten, optionale KI-Übersetzungen und Zusammenfassungen von Artikeln, ein begrenzter Chat-Assistent mit rein lesendem Zugriff und ein Marktüberblick für sechs Länder.
- Testquellen für Backend und Flutter, zehn Datenbankmigrationen, Konfigurationsbeispiele, Architektur- und API-Dokumente sowie historische Fortschritts- und Entscheidungsprotokolle.

## Wo die Arbeit endete

- Das für Phase 6 geplante Live-Prognosesystem mit eigener Rückkopplung ist unvollendet. Sein Assistentenwerkzeug meldet ausdrücklich, dass es nicht verfügbar ist, statt eine Prognose zu erfinden.
- Automatischer Wallex-Handel mit echtem Geld und der vorgeschlagene Ablauf zur Zuweisung eines Nutzerbudgets wurden nicht implementiert. Der Börsenadapter ist lediglich eine Mock-Schnittstelle.
- Für den Produktivbetrieb geeignete Datenvereinbarungen, unabhängig validierte finanzielle Ergebnisse, die Absicherung einer öffentlichen Bereitstellung und zuverlässiger Anbieterzugang bleiben offene Aufgaben.
- Zahlungsabwicklung, eine vollständige Portfolio-Oberfläche und einige sichtbare Einstellungen sind unvollendet. Ein Abonnement- und Berechtigungsmodell ist noch kein fertiges Bezahlsystem.
- Der aktuelle integrierte Quellcode enthält Grundgerüste für Windows und Web; das ältere Android-Grundgerüst ist separat erhalten. Eine funktionierende aktuelle Android- oder Web-Veröffentlichung wurde nicht verifiziert.

## Das Projekt fortsetzen

Beginnen Sie mit dem Leitfaden zur Weiterentwicklung, der Einrichtung aus einem frisch geklonten Repository, der aktuellen Statusübersicht und dem Prüfbericht. Historische Dokumente bleiben mit ihrem Datum erhalten; ihre Phasenbezeichnungen, Anbieterpreise und alten Testzahlen haben keinen Vorrang vor dem aktuellen Quellcode. Verwenden Sie eigene Dienstkonfigurationen und eine neue Datenbank. Private Kontodatenbanken, API-Zugangsdaten und die Android-Signieridentität werden nicht mitgeliefert.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## Markenmaterial und historische Unterlagen

Das bereitgestellte Projektposter und die Logos sind enthalten. Audiodateien werden als separates Asset-Paket auf Grundlage der Aussage des Urhebers verteilt, dass eine Weiterverbreitung zulässig ist; sie fallen nicht automatisch unter die Codelizenz. Ältere Quellcode-Snapshots sind historische Referenzen und keine beliebig austauschbaren Bestandteile der aktuellen App.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="Historisches Werbeposter: Es zeigt die ursprüngliche Projektvision, keine verifizierte aktuelle Veröffentlichung."></a></p>

*Historisches Werbeposter: Es zeigt die ursprüngliche Projektvision, keine verifizierte aktuelle Veröffentlichung.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## Technische Übergabe

Die ausführlichen technischen Leitfäden sind auf Englisch und stehen neben den erhaltenen ursprünglichen englischen und persischen Projektdokumenten. Diese Portfolio-Einführungen nutzen dieselben 18 Dokumentationssprachen wie der Rest des Portfolios; die 8 vorhandenen Oberflächensprachen der App sind eine separate Funktion.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

Lesen Sie vor der Wiederverwendung von Code oder Medien die Veröffentlichungs- und Lizenzdokumentation des Repositorys sowie die gesonderten Hinweise zu Drittanbieter-Assets.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
