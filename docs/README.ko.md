# GoldBrain 🧠✨

**7개월의 도전과 배움, 그리고 아직 완성되지 않은 금융 인텔리전스 작업 공간.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain은 쌍둥이 형제 Bardiya와 Armiya Alizadeh(Kabir)가 개발하다 중단한 실험 프로젝트입니다. 페르시아어 중심의 Flutter 인터페이스와 Python/FastAPI 백엔드를 결합합니다. 다른 개발자가 그동안의 작업을 이해하고 현재 상태를 재현한 뒤, 어떻게 이어 갈지 결정할 수 있도록 소스 코드를 보존합니다.

공동 제작자: **Bardiya Alizadeh (Kabir) · Farland_game**, **Armiya Alizadeh (Kabir) · ArmiyaFbix**. 프로젝트의 최신 정보 화면과 개발 기록에는 두 사람의 기여가 동등하게 명시되어 있습니다.

Bardiya에 따르면 약 7개월 동안 작업했으며, 프로그래밍 경험이 거의 없는 상태에서 실험과 온라인 자료, AI의 도움으로 배웠습니다. 처음에는 단기·장기 시장 예측을 제공하는 Windows/Android 제품을 만들고, 이후 사용자가 지정한 자금 일부만 활용하는 Wallex 자동매매를 추가하려 했습니다. 인프라 요구 사항, 비용, 복잡성, 금융 위험 때문에 그 전체 구상을 더 이상 추진하지 않았습니다. 이는 목표였으며, 완성되거나 검증된 기능이 아닙니다.

> 두뇌는 큰 계획을 세웠습니다. 인프라 청구서도 나름의 계획이 있었죠. 🧠🧾😅

## 보존된 소스 코드에 담긴 것

- 11개 테마, 기존 8개 인터페이스 언어, 애니메이션, 차트, 설정, 관심 목록, 오디오 제어 및 정보 페이지가 있는 자체 Flutter 인터페이스.
- 표준화된 시장 시세와 이력, 데이터 제공자 출처, 최신성 및 품질 검사, 영구 저장된 개요 데이터, 수집 워커를 갖춘 FastAPI 백엔드.
- 특징 계산, 시간 순서에 따른 평가·백테스트, 근거 기록을 포함하는 연구용 예측 엔진. 아직 완성되지 않은 최종 예측 시스템과는 구별됩니다.
- 모의투자 API. 화면에 보이는 포트폴리오 UI와 실제 자금 거래는 완성되지 않았습니다.
- 이메일 인증·비밀번호 재설정 절차, Argon2 비밀번호 처리, JWT 액세스 토큰, 갱신 토큰 순환 및 기기·세션 제어.
- RSS 뉴스, 선택적 AI 기사 번역·요약, 권한이 제한된 읽기 전용 채팅 도우미, 6개국 시장 흐름 지표.
- 백엔드와 Flutter 테스트 소스, 데이터베이스 마이그레이션 10개, 설정 예제, 아키텍처·API 문서, 과거 진행 상황과 의사결정 기록.

## 작업이 멈춘 지점

- 계획했던 Phase 6의 실시간·자체 피드백 예측 시스템은 미완성입니다. 해당 도우미 도구는 예측을 지어내는 대신 사용할 수 없다고 명확히 알립니다.
- Wallex 실제 자금 자동매매와 제안된 사용자 예산 할당 절차는 구현되지 않았습니다. 거래소 어댑터는 모의 인터페이스 계약입니다.
- 운영 수준의 데이터 이용 계약, 독립적으로 검증된 금융 성과, 공개 배포를 위한 보안·안정성 강화, 안정적인 제공자 접근은 앞으로 해결할 과제입니다.
- 결제 처리, 완전한 포트폴리오 UI와 화면에 보이는 일부 설정은 미완성입니다. 구독·이용 권한 모델이 있다고 해서 결제 시스템이 완성된 것은 아닙니다.
- 현재 통합 소스에는 Windows와 웹용 기본 구조가 있으며, 이전 Android 기본 구조는 별도로 보존되어 있습니다. 현재 버전의 Android 또는 웹 릴리스가 정상 작동하는지는 검증되지 않았습니다.

## 프로젝트 이어 가기

개발 이어받기 안내, 새로 복제한 저장소의 설정 방법, 현재 상태 표와 검증 보고서부터 읽어 주세요. 과거 문서는 날짜와 함께 보존되어 있으며, 그 안의 단계 명칭, 제공자 가격과 이전 테스트 수치는 현재 소스보다 우선하지 않습니다. 서비스는 직접 설정하고 새 데이터베이스를 사용해야 합니다. 개인 계정 데이터베이스, API 자격 증명과 Android 서명 정보는 제공하지 않습니다.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## 브랜딩과 과거 자료

제공된 프로젝트 포스터와 로고가 포함됩니다. 오디오는 재배포가 허용된다는 제작자의 진술을 바탕으로 별도 에셋 팩으로 배포되며, 코드 라이선스가 자동으로 적용되지는 않습니다. 이전 소스 스냅샷은 과거를 참고하기 위한 자료이지, 현재 앱에 서로 바꾸어 끼울 수 있는 구성 요소가 아닙니다.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="과거 홍보 포스터입니다. 검증된 현재 버전이 아니라 프로젝트의 초기 구상을 보여 줍니다."></a></p>

*과거 홍보 포스터입니다. 검증된 현재 버전이 아니라 프로젝트의 초기 구상을 보여 줍니다.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## 기술 인계

상세 기술 안내는 영어로 작성되었으며, 프로젝트의 기존 영어·페르시아어 문서도 보존되어 있습니다. 이 포트폴리오 소개는 나머지 포트폴리오와 동일한 문서 언어 18개를 사용합니다. 앱의 기존 인터페이스 언어 8개는 별도의 기능입니다.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

코드나 미디어를 재사용하기 전에 저장소의 공개·라이선스 기록과 별도의 제3자 에셋 고지를 읽어 주세요.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
