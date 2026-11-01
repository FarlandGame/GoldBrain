# GoldBrain 🧠✨

**Sept mois d'ambition et d'apprentissage, et un espace d'analyse financière resté inachevé.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain est un projet expérimental abandonné, créé par les frères jumeaux Bardiya et Armiya Alizadeh (Kabir). Il associe une interface Flutter pensée d'abord pour le persan à un backend Python/FastAPI. Le code source est conservé pour qu'un autre développeur puisse comprendre le travail réalisé, reproduire l'état actuel et décider de la suite à lui donner.

Cocréateurs : **Bardiya Alizadeh (Kabir) · Farland_game** et **Armiya Alizadeh (Kabir) · ArmiyaFbix**, crédités à parts égales dans le dernier écran À propos et les notes de développement du projet.

Bardiya décrit environ sept mois de travail, commencés avec peu d'expérience en programmation, puis un apprentissage par l'expérimentation, les ressources en ligne et l'aide de l'IA. L'ambition initiale était un produit Windows/Android proposant des prévisions de marché à court et à long terme, puis du trading automatique sur Wallex utilisant uniquement une part des fonds choisie par l'utilisateur. Il a cessé de poursuivre cette vision complète en raison des besoins d'infrastructure, des coûts, de la complexité et du risque financier. Il s'agissait d'objectifs, pas de fonctionnalités achevées ou validées.

> Le cerveau avait de grands projets. La facture d'infrastructure avait les siens. 🧠🧾😅

## Ce que contient le code source conservé

- Une interface Flutter personnalisée avec 11 thèmes, 8 langues d'interface existantes, des animations, des graphiques, des réglages, des listes de suivi, des commandes audio et une page À propos.
- Un backend FastAPI avec des cours et historiques de marché normalisés, la provenance des fournisseurs, des contrôles de fraîcheur et de qualité, des données de synthèse persistées et un processus de collecte.
- Un moteur de prévision destiné à la recherche, avec des caractéristiques calculées, des évaluations et backtests chronologiques et des enregistrements des éléments justificatifs ; il est distinct du prédicteur final inachevé.
- Des API de trading simulé, ou paper trading ; l'interface visible du portefeuille et le trading en argent réel ne sont pas achevés.
- Des parcours de vérification d'adresse e-mail et de réinitialisation du mot de passe, des mots de passe hachés avec Argon2, des jetons d'accès JWT, la rotation des jetons de renouvellement et la gestion des appareils et sessions.
- Des actualités RSS, des traductions et résumés d'articles par IA en option, un assistant de conversation limité à la lecture et un aperçu des marchés de six pays.
- Les sources des tests backend et Flutter, dix migrations de base de données, des exemples de configuration, des documents d'architecture et d'API, ainsi que l'historique des avancées et des décisions.

## Là où le travail s'est arrêté

- Le système de prévision en direct avec boucle de rétroaction prévu pour la Phase 6 est inachevé. Son outil destiné à l'assistant indique explicitement qu'il est indisponible plutôt que d'inventer une prévision.
- Le trading automatique en argent réel sur Wallex et le parcours envisagé d'allocation du budget utilisateur n'ont pas été implémentés. L'adaptateur de plateforme d'échange est une interface simulée.
- Les accords de données adaptés à la production, la validation indépendante des performances financières, le renforcement en vue d'un déploiement public et l'accès fiable aux fournisseurs restent à réaliser.
- Le traitement des paiements, l'interface complète du portefeuille et certains réglages visibles sont inachevés. Un modèle d'abonnement et de droits d'accès ne constitue pas un système de paiement terminé.
- Le code intégré actuel comprend des structures de base pour Windows et le Web ; l'ancienne structure Android est conservée séparément. Aucune version actuelle fonctionnelle pour Android ou le Web n'a été vérifiée.

## Reprendre le projet

Commencez par le guide de reprise, l'installation depuis un nouveau clone, la matrice d'état actuelle et le rapport de vérification. Les documents historiques sont conservés avec leur date ; leurs intitulés de phases, tarifs de fournisseurs et anciens nombres de tests ne priment pas sur le code actuel. Prévoyez votre propre configuration de services et une nouvelle base de données. Aucune base de comptes privés, aucun identifiant d'API ni aucune identité de signature Android n'est fourni.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## Identité visuelle et archives

L'affiche et les logos fournis pour le projet sont inclus. Les fichiers audio sont distribués dans un pack de ressources séparé, sur la déclaration du créateur selon laquelle leur redistribution est autorisée ; ils ne relèvent pas automatiquement de la licence du code. Les anciens instantanés du code source sont des références historiques, pas des composants interchangeables de l'application actuelle.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="Affiche promotionnelle historique : elle illustre la vision initiale du projet, pas une version actuelle vérifiée."></a></p>

*Affiche promotionnelle historique : elle illustre la vision initiale du projet, pas une version actuelle vérifiée.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## Transmission technique

Les guides techniques détaillés sont en anglais, aux côtés des documents originaux du projet conservés en anglais et en persan. Ces présentations utilisent les mêmes 18 langues de documentation que le reste du portfolio ; les 8 langues d'interface existantes de l'application constituent une fonctionnalité distincte.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

Avant de réutiliser le code ou les médias, consultez le dossier de publication et de licence du dépôt ainsi que les notices séparées concernant les ressources tierces.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
