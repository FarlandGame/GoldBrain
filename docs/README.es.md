# GoldBrain 🧠✨

**Siete meses de ambición y aprendizaje, y un espacio de inteligencia financiera que quedó sin terminar.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain es un proyecto experimental discontinuado de los hermanos gemelos Bardiya y Armiya Alizadeh (Kabir). Combina una interfaz Flutter diseñada principalmente para el persa con un backend Python/FastAPI. El código fuente se conserva para que otro desarrollador pueda comprender el trabajo, reproducir el estado actual y decidir cómo continuarlo.

Cocreadores: **Bardiya Alizadeh (Kabir) · Farland_game** y **Armiya Alizadeh (Kabir) · ArmiyaFbix**, acreditados por igual en la última pantalla Acerca de y en las notas de desarrollo del proyecto.

Bardiya cuenta que trabajó unos siete meses, empezando con poca experiencia en programación y aprendiendo mediante la experimentación, recursos en línea y ayuda de la IA. La ambición original era crear un producto para Windows y Android con predicciones de mercado a corto y largo plazo, y después operar automáticamente en Wallex utilizando solo la parte de los fondos que eligiera el usuario. Dejó de perseguir esa visión completa por los requisitos de infraestructura, los costes, la complejidad y el riesgo financiero. Eran objetivos, no capacidades terminadas ni validadas.

> El cerebro tenía grandes planes. La factura de infraestructura también tenía los suyos. 🧠🧾😅

## Qué contiene el código fuente conservado

- Una interfaz Flutter personalizada con 11 temas, 8 idiomas de interfaz existentes, animaciones, gráficos, ajustes, listas de seguimiento, controles de audio y una página Acerca de.
- Un backend FastAPI con cotizaciones e históricos de mercado normalizados, procedencia de los proveedores, comprobaciones de actualidad y calidad, datos de resumen persistentes y un proceso de recopilación.
- Un motor de predicción para investigación con características de datos, evaluación y backtesting cronológicos y registros de evidencias; es distinto del predictor final sin terminar.
- API de operaciones simuladas o paper trading; la interfaz visible de la cartera y las operaciones con dinero real no están completas.
- Flujos de verificación de correo y restablecimiento de contraseña, contraseñas con hash Argon2, tokens de acceso JWT, rotación de tokens de actualización y controles de dispositivos y sesiones.
- Noticias RSS, traducciones y resúmenes opcionales de artículos mediante IA, un asistente de chat limitado a consultas de solo lectura y una vista del pulso de los mercados de seis países.
- Código de pruebas del backend y de Flutter, diez migraciones de base de datos, ejemplos de configuración, documentos de arquitectura y API e historiales de progreso y decisiones.

## Dónde se detuvo el trabajo

- El sistema de predicción en directo con retroalimentación propia previsto para la Fase 6 está sin terminar. Su herramienta para el asistente informa expresamente de que no está disponible en lugar de inventar una predicción.
- No se implementaron las operaciones automáticas con dinero real en Wallex ni el flujo propuesto de asignación del presupuesto del usuario. El adaptador de la plataforma de intercambio es una interfaz simulada.
- Siguen pendientes los acuerdos de datos adecuados para producción, la validación independiente del rendimiento financiero, el refuerzo para un despliegue público y el acceso fiable a los proveedores.
- El procesamiento de pagos, la interfaz completa de cartera y algunos ajustes visibles están sin terminar. Un modelo de suscripciones y permisos no equivale a un sistema de compra y pago completo.
- El código integrado actual tiene estructuras iniciales para Windows y la Web; la estructura antigua de Android se conserva por separado. No se ha verificado una versión actual funcional de Android o de la Web.

## Retomar el proyecto

Empieza por la guía de continuación, la configuración desde un clon nuevo, la matriz de estado actual y el informe de verificación. Los documentos históricos se conservan con sus fechas; sus nombres de fases, precios de proveedores y recuentos antiguos de pruebas no prevalecen sobre el código actual. Utiliza tu propia configuración de servicios y una base de datos nueva. No se incluyen bases de datos de cuentas privadas, credenciales de API ni la identidad de firma de Android.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## Identidad visual y material histórico

Se incluyen el póster y los logotipos proporcionados para el proyecto. El audio se distribuye como un paquete de recursos independiente, basándose en la declaración del creador de que su redistribución está permitida; no queda cubierto automáticamente por la licencia del código. Las instantáneas antiguas del código fuente son referencias históricas, no componentes intercambiables de la aplicación actual.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="Póster promocional histórico: muestra la visión original del proyecto, no una versión actual verificada."></a></p>

*Póster promocional histórico: muestra la visión original del proyecto, no una versión actual verificada.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## Entrega técnica

Las guías técnicas detalladas están en inglés, junto a los documentos originales del proyecto conservados en inglés y persa. Estas presentaciones usan los mismos 18 idiomas de documentación que el resto del portfolio; los 8 idiomas de interfaz existentes de la aplicación son una función independiente.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

Antes de reutilizar código o medios, lee el registro de publicación y licencia del repositorio y los avisos independientes sobre recursos de terceros.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
