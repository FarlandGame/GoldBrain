# GoldBrain 🧠✨

**Sette mesi di ambizione, apprendimento e uno spazio di lavoro per l'analisi finanziaria rimasto incompiuto.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain è un progetto sperimentale interrotto dei fratelli gemelli Bardiya e Armiya Alizadeh (Kabir). Unisce un'interfaccia Flutter pensata innanzitutto per il persiano a un backend Python/FastAPI. Il codice sorgente è conservato affinché un altro sviluppatore possa capire il lavoro svolto, riprodurne lo stato attuale e decidere come proseguirlo.

Coautori: **Bardiya Alizadeh (Kabir) · Farland_game** e **Armiya Alizadeh (Kabir) · ArmiyaFbix**, accreditati alla pari nella più recente schermata Informazioni e nelle note di sviluppo del progetto.

Bardiya racconta circa sette mesi di lavoro, iniziati con poca esperienza di programmazione e proseguiti imparando tramite esperimenti, risorse online e assistenza dell'IA. L'ambizione iniziale era un prodotto Windows/Android con previsioni di mercato a breve e lungo termine, seguito dal trading automatico su Wallex usando soltanto una quota dei fondi scelta dall'utente. Ha smesso di perseguire questa visione completa a causa delle esigenze infrastrutturali, dei costi, della complessità e del rischio finanziario. Erano obiettivi, non funzionalità completate o validate.

> Il cervello aveva grandi progetti. Anche la fattura dell'infrastruttura aveva i suoi. 🧠🧾😅

## Che cosa contiene il codice conservato

- Un'interfaccia Flutter personalizzata con 11 temi, 8 lingue di interfaccia già presenti, animazioni, grafici, impostazioni, liste di osservazione, controlli audio e una pagina Informazioni.
- Un backend FastAPI con quotazioni e dati storici di mercato normalizzati, provenienza dei fornitori, controlli di aggiornamento e qualità, dati riepilogativi persistenti e un processo di raccolta.
- Un motore di previsione sperimentale con variabili calcolate, valutazione cronologica/backtesting e registri delle evidenze; è distinto dal predittore finale rimasto incompiuto.
- API per il trading simulato; l'interfaccia visibile del portafoglio e il trading con denaro reale non sono completi.
- Flussi di verifica dell'e-mail e reimpostazione della password, password con Argon2, token di accesso JWT, rotazione dei token di aggiornamento e controlli di dispositivi e sessioni.
- Notizie RSS, traduzioni e riassunti facoltativi degli articoli tramite IA, un assistente di chat limitato e in sola lettura e una panoramica dei mercati di sei paesi.
- Codice dei test del backend e di Flutter, dieci migrazioni del database, esempi di configurazione, documenti di architettura/API e registri storici dei progressi e delle decisioni.

## Dove si è fermato il lavoro

- Il sistema di previsione in tempo reale con retroazione sui propri risultati previsto per la Fase 6 è incompiuto. Il relativo strumento dell'assistente segnala esplicitamente che non è disponibile, invece di inventare una previsione.
- Il trading automatico con denaro reale su Wallex e il flusso proposto per assegnare il budget dell'utente non sono stati implementati. L'adattatore dell'exchange è un'interfaccia simulata.
- Restano da affrontare gli accordi sui dati adatti alla produzione, la validazione indipendente delle prestazioni finanziarie, il rafforzamento per una distribuzione pubblica e l'accesso affidabile ai fornitori.
- L'elaborazione dei pagamenti, un'interfaccia completa del portafoglio e alcune impostazioni visibili sono incompiute. Un modello di abbonamenti e diritti di accesso non è un sistema di acquisto completo.
- Il codice integrato attuale contiene strutture iniziali per Windows e web; la vecchia struttura Android è conservata separatamente. Non è stata verificata una versione attuale funzionante per Android o web.

## Riprendi il progetto

Inizia dalla guida per proseguire il lavoro, dalla configurazione di un clone nuovo, dalla matrice dello stato attuale e dal rapporto di verifica. I documenti storici sono conservati con le loro date; le loro etichette di fase, i prezzi dei fornitori e i vecchi conteggi dei test non prevalgono sul codice attuale. Usa la tua configurazione dei servizi e un database nuovo. Non vengono forniti database di account privati, credenziali API o identità di firma Android.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## Identità visiva e materiale storico

Sono inclusi il poster e i loghi forniti per il progetto. L'audio è distribuito come pacchetto di risorse separato sulla base della dichiarazione del creatore che ne autorizza la ridistribuzione; non è automaticamente coperto dalla licenza del codice. Le vecchie istantanee del codice sono riferimenti storici, non componenti intercambiabili dell'app attuale.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="Poster promozionale storico: illustra la visione originale del progetto, non una versione attuale verificata."></a></p>

*Poster promozionale storico: illustra la visione originale del progetto, non una versione attuale verificata.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## Passaggio di consegne tecnico

Le guide tecniche dettagliate sono in inglese, insieme ai documenti originali del progetto in inglese e persiano che sono stati conservati. Queste presentazioni usano le stesse 18 lingue di documentazione del resto del portfolio; le 8 lingue di interfaccia già presenti nell'app sono una caratteristica distinta.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

Leggi il registro di pubblicazione/licenza del repository e le informative separate sulle risorse di terze parti prima di riutilizzare codice o contenuti multimediali.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
