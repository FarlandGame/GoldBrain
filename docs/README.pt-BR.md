# GoldBrain 🧠✨

**Sete meses de ambição, aprendizado e um ambiente de inteligência financeira que ficou inacabado.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain é um projeto experimental descontinuado dos irmãos gêmeos Bardiya e Armiya Alizadeh (Kabir). Ele combina uma interface Flutter pensada primeiro para o persa com um backend em Python/FastAPI. O código-fonte foi preservado para que outro desenvolvedor possa entender o trabalho, reproduzir o estado atual e decidir como continuá-lo.

Cocriadores: **Bardiya Alizadeh (Kabir) · Farland_game** e **Armiya Alizadeh (Kabir) · ArmiyaFbix**, com créditos iguais na versão mais recente da tela Sobre e nas notas de desenvolvimento do projeto.

Bardiya relata cerca de sete meses de trabalho, começando com pouca experiência em programação e aprendendo por meio de experimentos, recursos on-line e assistência de IA. A ambição original era criar um produto para Windows/Android com previsões de mercado de curto e longo prazo e, depois, operações automatizadas na Wallex usando apenas uma parcela dos recursos escolhida pelo usuário. Ele deixou de perseguir essa visão completa devido às exigências de infraestrutura, aos custos, à complexidade e ao risco financeiro. Eram objetivos, não recursos concluídos ou validados.

> O cérebro tinha grandes planos. A conta da infraestrutura também. 🧠🧾😅

## O que o código-fonte preservado contém

- Uma interface Flutter personalizada com 11 temas, 8 idiomas de interface existentes, animações, gráficos, configurações, listas de acompanhamento, controles de áudio e uma página Sobre.
- Um backend FastAPI com cotações e histórico de mercado normalizados, identificação da origem dos provedores, verificações de atualidade e qualidade, dados persistidos de visão geral e um processo de coleta.
- Um mecanismo experimental de previsão com variáveis calculadas, avaliação cronológica/backtesting e registros de evidências; ele é diferente do preditor final que ficou inacabado.
- APIs de negociação simulada; a interface visível de carteira e a negociação com dinheiro real não estão completas.
- Fluxos de verificação de e-mail e redefinição de senha, senhas com Argon2, tokens de acesso JWT, rotação de tokens de atualização e controles de dispositivos e sessões.
- Notícias RSS, tradução e resumos opcionais de artigos por IA, um assistente de chat limitado e somente de leitura e um panorama dos mercados de seis países.
- Código-fonte dos testes do backend e do Flutter, dez migrações de banco de dados, exemplos de configuração, documentos de arquitetura/API e registros históricos de progresso e decisões.

## Onde o trabalho parou

- O sistema de previsão ao vivo com realimentação própria planejado para a Fase 6 está inacabado. Sua ferramenta para o assistente informa explicitamente que está indisponível, em vez de inventar uma previsão.
- A negociação automática com dinheiro real na Wallex e o fluxo proposto de alocação do orçamento do usuário não foram implementados. O adaptador da corretora é uma interface simulada.
- Acordos de dados adequados à produção, desempenho financeiro validado de forma independente, reforço para implantação pública e acesso confiável aos provedores continuam pendentes.
- O processamento de pagamentos, uma interface completa de carteira e algumas configurações visíveis estão inacabados. Um modelo de assinatura e permissões de acesso não equivale a um sistema de checkout concluído.
- O código integrado atual tem estruturas iniciais para Windows e web; a estrutura Android mais antiga foi preservada separadamente. Não foi verificada uma versão funcional atual para Android ou web.

## Continue o projeto

Comece pelo guia de continuidade, pela configuração após uma nova clonagem, pela matriz de estado atual e pelo relatório de verificação. Os documentos históricos foram mantidos com suas datas; seus rótulos de fase, preços de provedores e contagens antigas de testes não se sobrepõem ao código atual. Use suas próprias configurações de serviços e um banco de dados novo. Nenhum banco de contas privadas, credencial de API ou identidade de assinatura Android é fornecido.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## Identidade visual e material histórico

O pôster e os logotipos fornecidos do projeto estão incluídos. O áudio é distribuído como um pacote de recursos separado, com base na declaração do criador de que a redistribuição é permitida; ele não está automaticamente coberto pela licença do código. Versões antigas do código-fonte são referências históricas, não componentes intercambiáveis do aplicativo atual.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="Pôster promocional histórico: ilustra a visão original do projeto, não uma versão atual verificada."></a></p>

*Pôster promocional histórico: ilustra a visão original do projeto, não uma versão atual verificada.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## Transferência técnica

Os guias técnicos detalhados estão em inglês, junto dos documentos originais do projeto em inglês e persa que foram preservados. Estas apresentações do portfólio usam os mesmos 18 idiomas de documentação do restante do portfólio; os 8 idiomas de interface já existentes no aplicativo são um recurso separado.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

Leia o registro de publicação/licença do repositório e os avisos separados sobre recursos de terceiros antes de reutilizar código ou mídia.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
