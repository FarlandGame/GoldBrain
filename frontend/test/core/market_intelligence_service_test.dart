import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/market_intelligence_service.dart';

void main() {
  MarketIntelligenceInput input({
    String symbol = 'XAU',
    String quoteUnit = 'USD',
    String historyUnit = 'USD',
    String language = 'persian',
    bool includeNews = true,
    bool relatedNews = true,
    int historyPoints = 16,
    DateTime? historyStart,
    DateTime? collectedAt,
    DateTime? quoteUpdatedAt,
    DateTime? newsPublishedAt,
    double historyStep = 0.00075,
    List<double>? historyFactors,
  }) {
    final collected = collectedAt ?? DateTime.utc(2026, 8, 10, 20);
    final basePrice = switch (symbol) {
      'BTC' => 63000.0,
      'ETH' => 1800.0,
      'GOLD18' => 19000000.0,
      'USD' => 187000.0,
      'XAG' => 65.0,
      _ => 4330.0,
    };
    final quotePrice = switch (symbol) {
      'BTC' => 64000.0,
      'ETH' => 1875.0,
      'GOLD18' => 19100000.0,
      'USD' => 187500.0,
      'XAG' => 65.5,
      _ => 4383.2,
    };
    return MarketIntelligenceInput(
      languageCode: language,
      collectedAt: collected,
      quotes: <IntelligenceQuoteEvidence>[
        IntelligenceQuoteEvidence(
          symbol: symbol,
          price: quotePrice,
          unit: quoteUnit,
          changePercent: 0.35,
          updatedAt:
              quoteUpdatedAt ?? collected.subtract(const Duration(minutes: 1)),
          source: 'verified-live-test',
        ),
      ],
      news: includeNews
          ? <IntelligenceNewsEvidence>[
              IntelligenceNewsEvidence(
                id: 'news-1',
                title: relatedNews
                    ? switch (symbol) {
                        'BTC' => 'خبر تازه بیت کوین',
                        'ETH' => 'خبر تازه اتریوم',
                        'USD' => 'خبر تازه دلار',
                        'XAG' => 'خبر تازه نقره',
                        _ => 'خبر تازه بازار طلا',
                      }
                    : 'خبر صنعت خودروسازی',
                summary: 'این گزارش از یک منبع مشخص دریافت شده است.',
                publishedAt:
                    newsPublishedAt ??
                    collected.subtract(const Duration(hours: 2)),
                source: 'test-news',
              ),
            ]
          : const <IntelligenceNewsEvidence>[],
      histories: (historyFactors?.isEmpty ?? historyPoints == 0)
          ? const <IntelligenceHistoryEvidence>[]
          : <IntelligenceHistoryEvidence>[
              IntelligenceHistoryEvidence(
                symbol: symbol,
                unit: historyUnit,
                source: 'verified-test-history',
                points: List<IntelligenceHistoryPoint>.generate(
                  historyFactors?.length ?? historyPoints,
                  (index) => IntelligenceHistoryPoint(
                    time:
                        (historyStart ??
                                collected.subtract(const Duration(hours: 16)))
                            .add(Duration(hours: index)),
                    close:
                        basePrice *
                        (historyFactors?[index] ?? 1 + index * historyStep),
                  ),
                ),
              ),
            ],
    );
  }

  test(
    'parses a sourced scenario and deterministic technical features',
    () async {
      final service = MarketIntelligenceService(
        clock: () => DateTime.utc(2026, 8, 10, 20),
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async {
              expect(
                systemPrompt,
                contains('uncalibrated AI scenario estimate'),
              );
              expect(
                systemPrompt,
                contains('always return null for both target fields'),
              );
              expect(
                messages.single.content,
                contains('deterministic_features'),
              );
              expect(messages.single.content, contains('rsi_14'));
              return '''
              {"reports":[{"symbol":"XAU","direction":"upward",
              "scenario_estimate_percent":67,
              "forecast_target_price":4420,
              "forecast_target_unit":"USD",
              "summary":"سناریوی صعودی مشروط برای بازار طلا مطرح است.",
              "reasons":["روند قیمت منبع‌دار در این بازه مثبت بوده است."]}]}
            ''';
            },
      );

      final report = await service.analyze(input());

      expect(report.symbol, 'XAU');
      expect(report.direction, MarketScenarioDirection.upward);
      expect(report.scenarioEstimatePercent, 67);
      expect(report.forecastTargetPrice, greaterThan(4383.2));
      expect(report.forecastTargetPrice, isNot(4420));
      expect(report.forecastTargetSymbol, 'XAU');
      expect(report.forecastTargetUnit, 'USD');
      expect(report.historyPointCount, 16);
      expect(report.relevantNewsCount, 1);
      expect(
        report.forecastFor.difference(report.generatedAt),
        const Duration(hours: 12),
      );
    },
  );

  test('accepts only closed unambiguous direction aliases', () async {
    final aliases =
        <({String value, MarketScenarioDirection expected, bool flatHistory})>[
          (
            value: ' UpWaRd ',
            expected: MarketScenarioDirection.upward,
            flatHistory: false,
          ),
          (
            value: 'bullish',
            expected: MarketScenarioDirection.upward,
            flatHistory: false,
          ),
          (
            value: 'صعودی',
            expected: MarketScenarioDirection.upward,
            flatHistory: false,
          ),
          (
            value: 'direction: upward',
            expected: MarketScenarioDirection.upward,
            flatHistory: false,
          ),
          (
            value: 'upward (صعودی)',
            expected: MarketScenarioDirection.upward,
            flatHistory: false,
          ),
          (
            value: 'روند افزایشی',
            expected: MarketScenarioDirection.upward,
            flatHistory: false,
          ),
          (
            value: 'DOWNWARD',
            expected: MarketScenarioDirection.downward,
            flatHistory: false,
          ),
          (
            value: 'bearish',
            expected: MarketScenarioDirection.downward,
            flatHistory: false,
          ),
          (
            value: 'نزولی',
            expected: MarketScenarioDirection.downward,
            flatHistory: false,
          ),
          (
            value: 'trend: falling',
            expected: MarketScenarioDirection.downward,
            flatHistory: false,
          ),
          (
            value: 'sideways',
            expected: MarketScenarioDirection.neutral,
            flatHistory: true,
          ),
          (
            value: 'خنثی',
            expected: MarketScenarioDirection.neutral,
            flatHistory: true,
          ),
          (
            value: 'stable',
            expected: MarketScenarioDirection.neutral,
            flatHistory: true,
          ),
          (
            value: 'insufficient data',
            expected: MarketScenarioDirection.insufficientData,
            flatHistory: true,
          ),
          (
            value: 'insufficient-data',
            expected: MarketScenarioDirection.insufficientData,
            flatHistory: true,
          ),
          (
            value: 'insufficientData',
            expected: MarketScenarioDirection.insufficientData,
            flatHistory: true,
          ),
          (
            value: 'داده ناکافی',
            expected: MarketScenarioDirection.insufficientData,
            flatHistory: true,
          ),
        ];

    for (final alias in aliases) {
      final service = MarketIntelligenceService(
        clock: () => DateTime.utc(2026, 8, 10, 20),
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async =>
                '''{"reports":[{"symbol":"XAU","direction":"${alias.value}","scenario_estimate_percent":60,"forecast_target_price":null,"forecast_target_unit":null,"summary":"شواهد منبع‌دار بازار در این بازه بررسی شده است.","reasons":["روند قیمت منبع‌دار در ورودی موجود است."]}]}''',
      );
      addTearDown(service.close);

      final report = await service.analyze(
        input(historyStep: alias.flatHistory ? 0 : 0.00075),
      );
      expect(report.direction, alias.expected, reason: alias.value);
    }

    var invalidCalls = 0;
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async {
            invalidCalls++;
            return '''{"reports":[{"symbol":"XAU","direction":"maybe_up","scenario_estimate_percent":60,"forecast_target_price":null,"forecast_target_unit":null,"summary":"شواهد منبع‌دار بازار بررسی شده است.","reasons":["روند قیمت منبع‌دار موجود است."]}]}''';
          },
    );
    addTearDown(service.close);

    await expectLater(
      service.analyze(input()),
      throwsA(
        isA<MarketIntelligenceException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
    expect(invalidCalls, 2);
  });

  test(
    'retries an invalid direction once and accepts the correction',
    () async {
      var calls = 0;
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async {
              calls++;
              if (calls == 1) {
                return '{"direction":"maybe_up","scenario_estimate_percent":60,'
                    '"summary":"The sourced market evidence was reviewed.",'
                    '"reasons":["Verified price history is available."]}';
              }
              expect(
                messages.single.content,
                contains('Classify each supplied asset'),
              );
              expect(
                systemPrompt,
                contains('strict market-direction classifier'),
              );
              expect(temperature, 0);
              return '{"direction":"upward"}';
            },
      );
      addTearDown(service.close);

      final report = await service.analyze(input(language: 'english'));

      expect(calls, 2);
      expect(report.direction, MarketScenarioDirection.upward);
      expect(report.summary, 'The sourced market evidence was reviewed.');
    },
  );

  test(
    'direction-only repair cannot manufacture missing report evidence',
    () async {
      var calls = 0;
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async {
              calls++;
              if (calls == 1) {
                return '{"direction":"maybe_up",'
                    '"scenario_estimate_percent":60}';
              }
              return '{"direction":"upward"}';
            },
      );
      addTearDown(service.close);

      await expectLater(
        service.analyze(input(language: 'english')),
        throwsA(
          isA<MarketIntelligenceException>().having(
            (error) => error.code,
            'code',
            'invalid_response',
          ),
        ),
      );
      expect(calls, 2);
    },
  );

  test(
    'language repair follows a valid direction repair when both were invalid',
    () async {
      var calls = 0;
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async {
              calls++;
              if (calls == 1) {
                return '{"direction":"maybe_up",'
                    '"scenario_estimate_percent":60,'
                    '"summary":"The sourced market evidence was reviewed.",'
                    '"reasons":["Verified history is available."]}';
              }
              if (calls == 2) {
                expect(
                  systemPrompt,
                  contains('strict market-direction classifier'),
                );
                return '{"direction":"upward"}';
              }
              expect(messages.single.content, contains('wrong language'));
              return '{"direction":"upward",'
                  '"scenario_estimate_percent":60,'
                  '"summary":"شواهد منبع‌دار از یک سناریوی صعودی مشروط پشتیبانی می‌کند.",'
                  '"reasons":["روند قیمت تأییدشده در بازهٔ بررسی مثبت است."]}';
            },
      );
      addTearDown(service.close);

      final report = await service.analyze(input(language: 'persian'));

      expect(calls, 3);
      expect(report.direction, MarketScenarioDirection.upward);
      expect(report.languageCode, 'persian');
    },
  );

  test('repairs only the invalid report in a mixed batch', () async {
    var calls = 0;
    final xauInput = input(language: 'english');
    final xagInput = input(symbol: 'XAG', language: 'english');
    final batchInput = MarketIntelligenceInput(
      languageCode: 'english',
      quotes: <IntelligenceQuoteEvidence>[
        ...xauInput.quotes,
        ...xagInput.quotes,
      ],
      news: <IntelligenceNewsEvidence>[...xauInput.news, ...xagInput.news],
      histories: <IntelligenceHistoryEvidence>[
        ...xauInput.histories,
        ...xagInput.histories,
      ],
      collectedAt: xauInput.collectedAt,
    );
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async {
            calls++;
            if (calls == 1) {
              return '''{"reports":[
                {"symbol":"XAU","direction":"neutral","scenario_estimate_percent":52,
                 "summary":"Gold evidence is mixed in the observed window.",
                 "reasons":["Verified timeframes do not fully align."]},
                {"symbol":"XAG","direction":"upward/downward","scenario_estimate_percent":58,
                 "summary":"Silver evidence was reviewed.",
                 "reasons":["Verified price history is available."]}
              ]}''';
            }
            expect(messages.single.content, contains('"symbol":"XAG"'));
            expect(messages.single.content, isNot(contains('"symbol":"XAU"')));
            return '''{"reports":[
              {"symbol":"XAG","direction":"upward","scenario_estimate_percent":58,
               "summary":"Silver supports a conditional upward scenario.",
               "reasons":["Verified price momentum is positive."]}
            ]}''';
          },
    );
    addTearDown(service.close);

    final result = await service.analyzeBatch(
      batchInput,
      symbols: const <String>{'XAU', 'XAG'},
    );

    expect(calls, 2);
    expect(result.issues, isEmpty);
    expect(result.reports.keys, containsAll(<String>['XAU', 'XAG']));
  });

  test('analyzes multiple assets with one batch completion', () async {
    var calls = 0;
    final xauInput = input();
    final xagInput = input(symbol: 'XAG');
    final batchInput = MarketIntelligenceInput(
      languageCode: 'persian',
      quotes: <IntelligenceQuoteEvidence>[
        ...xauInput.quotes,
        ...xagInput.quotes,
      ],
      news: <IntelligenceNewsEvidence>[...xauInput.news, ...xagInput.news],
      histories: <IntelligenceHistoryEvidence>[
        ...xauInput.histories,
        ...xagInput.histories,
      ],
      collectedAt: xauInput.collectedAt,
    );
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async {
            calls++;
            return '''{"reports":[
              {"symbol":"XAU","direction":"neutral","scenario_estimate_percent":52,
               "forecast_target_price":null,"forecast_target_unit":null,
               "summary":"شواهد بازار طلا در حال حاضر ترکیبی است.",
               "reasons":["روند کوتاه و بلند هم‌جهت نیستند."]},
              {"symbol":"XAG","direction":"upward","scenario_estimate_percent":61,
               "forecast_target_price":66,"forecast_target_unit":"USD",
               "summary":"سناریوی صعودی مشروط برای نقره دیده می‌شود.",
               "reasons":["حرکت قیمت نقره در بازه بررسی‌شده مثبت است."]}
            ]}''';
          },
    );

    final result = await service.analyzeBatch(
      batchInput,
      symbols: const <String>{'XAU', 'XAG'},
    );

    expect(calls, 1);
    expect(result.issues, isEmpty);
    expect(result.reports.keys, containsAll(<String>['XAU', 'XAG']));
  });

  test(
    'does not accept an unexplained neutral result against aligned upward indicators',
    () async {
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async {
              expect(
                messages.single.content,
                contains('deterministic_technical_bias'),
              );
              expect(systemPrompt, contains('neutral_conflict_news_ids'));
              return '{"direction":"neutral","scenario_estimate_percent":51,'
                  '"forecast_target_price":null,"forecast_target_unit":null,'
                  '"summary":"شواهد فعلی بازار در یک سناریوی خنثی قرار دارد.",'
                  '"reasons":["اطلاعات برای تعیین جهت کافی به نظر نمی‌رسد."]}';
            },
      );

      final report = await service.analyze(input());

      expect(report.direction, MarketScenarioDirection.upward);
      expect(report.scenarioEstimatePercent, greaterThanOrEqualTo(56));
      expect(report.summary, contains('صعودی'));
      expect(report.summary, isNot(contains('خنثی')));
    },
  );

  test(
    'does not accept an unexplained neutral result against aligned downward indicators',
    () async {
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async =>
                '{"direction":"neutral","scenario_estimate_percent":50,'
                '"forecast_target_price":null,"forecast_target_unit":null,'
                '"summary":"شواهد فعلی بازار در یک سناریوی خنثی قرار دارد.",'
                '"reasons":["اطلاعات برای تعیین جهت کافی به نظر نمی‌رسد."]}',
      );

      final report = await service.analyze(input(historyStep: -0.00075));

      expect(report.direction, MarketScenarioDirection.downward);
      expect(report.scenarioEstimatePercent, greaterThanOrEqualTo(56));
      expect(report.summary, contains('نزولی'));
    },
  );

  test(
    'keeps neutral when deterministic indicators are genuinely mixed',
    () async {
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async =>
                '{"direction":"neutral","scenario_estimate_percent":50,'
                '"forecast_target_price":null,"forecast_target_unit":null,'
                '"summary":"حرکت‌های محاسبه‌شده بازار ترکیبی و بدون جهت غالب هستند.",'
                '"reasons":["مومنتوم‌های کوتاه و دوره‌ای جهت یکسانی ندارند."]}',
      );

      final report = await service.analyze(
        input(
          historyFactors: const <double>[
            1,
            1.001,
            0.999,
            1.001,
            0.999,
            1,
            1.001,
            0.999,
            1.001,
            0.999,
            1,
            1.001,
            0.999,
            1.001,
            0.999,
            1,
          ],
        ),
      );

      expect(report.direction, MarketScenarioDirection.neutral);
      expect(report.scenarioEstimatePercent, 50);
    },
  );

  test(
    'keeps neutral when the model cites a supplied conflicting news item',
    () async {
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async =>
                '{"direction":"neutral","scenario_estimate_percent":53,'
                '"forecast_target_price":null,"forecast_target_unit":null,'
                '"neutral_conflict_news_ids":["news-1"],'
                '"summary":"روند قیمت مثبت است اما خبر مرتبط با آن تعارض دارد.",'
                '"reasons":["خبر منبع‌دار news-1 با جهت شاخص‌های فنی همسو نیست."]}',
      );

      final report = await service.analyze(input());

      expect(report.direction, MarketScenarioDirection.neutral);
      expect(report.scenarioEstimatePercent, 53);
    },
  );

  test('caps confidence when no news is directly related', () async {
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async =>
              '{"direction":"upward","scenario_estimate_percent":95,'
              '"forecast_target_price":4400,"forecast_target_unit":"USD",'
              '"summary":"سناریوی صعودی با محدودیت شواهد خبری مطرح است.",'
              '"reasons":["خبر مرتبط مستقیمی برای این دارایی وجود ندارد."]}',
    );

    final report = await service.analyze(input(relatedNews: false));

    expect(report.relevantNewsCount, 0);
    expect(report.scenarioEstimatePercent, lessThanOrEqualTo(60));
  });

  test(
    'allows technical-only analysis without news and caps confidence',
    () async {
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async {
              expect(
                messages.single.content,
                contains('technical-only analysis'),
              );
              return '{"direction":"upward","scenario_estimate_percent":88,'
                  '"forecast_target_price":4400,"forecast_target_unit":"USD",'
                  '"summary":"تحلیل فقط بر داده فنی منبع‌دار تکیه دارد.",'
                  '"reasons":["در این نوبت خبر منبع‌داری در دسترس نیست."]}';
            },
      );

      final report = await service.analyze(input(includeNews: false));

      expect(report.direction, MarketScenarioDirection.upward);
      expect(report.relevantNewsCount, 0);
      expect(report.scenarioEstimatePercent, lessThanOrEqualTo(60));
    },
  );

  test(
    'anchors BTC target to exact USD history without treating USDT as USD',
    () async {
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async {
              expect(
                messages.single.content,
                contains('"target_unit_if_allowed":"USD"'),
              );
              expect(
                messages.single.content,
                contains('exact_history_latest_close'),
              );
              return '{"direction":"upward","scenario_estimate_percent":68,'
                  '"forecast_target_price":64600,"forecast_target_unit":"USD",'
                  '"summary":"سناریوی صعودی مشروط برای بیت کوین مطرح است.",'
                  '"reasons":["هدف فقط بر تاریخچه دلاری همان نماد متکی است."]}';
            },
      );

      final report = await service.analyze(
        input(symbol: 'BTC', quoteUnit: 'USDT', historyUnit: 'USD'),
      );

      expect(report.forecastTargetPrice, greaterThan(63700));
      expect(report.forecastTargetPrice, isNot(64600));
      expect(report.forecastTargetUnit, 'USD');
    },
  );

  test('ignores a BTC model target mislabeled as USDT', () async {
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async =>
              '{"direction":"upward","scenario_estimate_percent":68,'
              '"forecast_target_price":64600,"forecast_target_unit":"USDT",'
              '"summary":"سناریوی صعودی مشروط برای بیت کوین مطرح است.",'
              '"reasons":["واحد هدف مدل با تاریخچه سازگار نیست."]}',
    );

    final report = await service.analyze(
      input(symbol: 'BTC', quoteUnit: 'USDT', historyUnit: 'USD'),
    );

    expect(report.forecastTargetPrice, greaterThan(63700));
    expect(report.forecastTargetPrice, isNot(64600));
    expect(report.forecastTargetUnit, 'USD');
  });

  test('rejects a 12-hour target backed only by stale history', () async {
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async {
            expect(messages.single.content, contains('"target_allowed":false'));
            return '{"direction":"upward","scenario_estimate_percent":90,'
                '"forecast_target_price":4420,"forecast_target_unit":"USD",'
                '"summary":"تاریخچه برای هدف کوتاه‌مدت به اندازه کافی تازه نیست.",'
                '"reasons":["آخرین داده تاریخی از افق پیش‌بینی فاصله دارد."]}';
          },
    );

    final report = await service.analyze(
      input(historyStart: DateTime.utc(2026, 8, 8, 4)),
    );

    expect(report.forecastTargetPrice, isNull);
    expect(report.scenarioEstimatePercent, lessThanOrEqualTo(55));
  });

  test('does not create a new target from a stale live quote', () async {
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async {
            expect(messages.single.content, contains('"target_allowed":false'));
            return '{"direction":"upward","scenario_estimate_percent":88,'
                '"forecast_target_price":4420,"forecast_target_unit":"USD",'
                '"summary":"قیمت زنده برای هدف کوتاه‌مدت به اندازه کافی تازه نیست.",'
                '"reasons":["آخرین قیمت بیش از بازه مجاز فاصله دارد."]}';
          },
    );

    final report = await service.analyze(
      input(quoteUpdatedAt: DateTime.utc(2026, 8, 10, 18)),
    );

    expect(report.forecastTargetPrice, isNull);
    expect(report.scenarioEstimatePercent, lessThanOrEqualTo(55));
  });

  test(
    'accepts a sourced domestic quote inside Navasan free-plan cadence',
    () async {
      final collected = DateTime.utc(2026, 8, 10, 20);
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async {
              expect(
                messages.single.content,
                contains('"target_allowed":true'),
              );
              return '{"direction":"upward","scenario_estimate_percent":61,'
                  '"forecast_target_price":19200000,"forecast_target_unit":"IRT",'
                  '"summary":"سناریوی صعودی مشروط برای طلای داخلی مطرح است.",'
                  '"reasons":["قیمت و تاریخچه منبع‌دار در بازه معتبر قرار دارند."]}';
            },
      );

      final report = await service.analyze(
        input(
          symbol: 'GOLD18',
          quoteUnit: 'IRT',
          historyUnit: 'IRT',
          collectedAt: collected,
          quoteUpdatedAt: collected.subtract(const Duration(hours: 2)),
        ),
      );

      expect(report.forecastTargetPrice, greaterThan(19100000));
      expect(report.forecastTargetPrice, isNot(19200000));
      expect(report.forecastTargetUnit, 'IRT');
    },
  );

  test('prefers fresh 24-hour history over a stale weekly fallback', () async {
    final collected = DateTime.utc(2026, 8, 10, 20);
    final base = input(
      symbol: 'GOLD18',
      quoteUnit: 'IRT',
      historyUnit: 'IRT',
      collectedAt: collected,
    );
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async =>
              '{"direction":"upward","scenario_estimate_percent":59,'
              '"forecast_target_price":19200000,"forecast_target_unit":"IRT",'
              '"summary":"تاریخچه تازه سناریوی مشروط را پشتیبانی می‌کند.",'
              '"reasons":["تیک‌های واقعی ۲۴ ساعت اخیر تازه‌تر هستند."]}',
    );
    final report = await service.analyze(
      MarketIntelligenceInput(
        languageCode: base.languageCode,
        quotes: base.quotes,
        news: base.news,
        collectedAt: collected,
        histories: <IntelligenceHistoryEvidence>[
          IntelligenceHistoryEvidence(
            symbol: 'GOLD18',
            unit: 'IRT',
            source: 'stale-daily-fallback',
            range: 'oneWeek',
            points: List.generate(
              8,
              (index) => IntelligenceHistoryPoint(
                time: collected
                    .subtract(const Duration(days: 10))
                    .add(Duration(days: index)),
                close: 18800000 + (index * 10000),
              ),
            ),
          ),
          IntelligenceHistoryEvidence(
            symbol: 'GOLD18',
            unit: 'IRT',
            source: 'Navasan · 18ayar · real tick history',
            range: 'oneDay',
            points: List.generate(
              12,
              (index) => IntelligenceHistoryPoint(
                time: collected
                    .subtract(const Duration(hours: 11))
                    .add(Duration(hours: index)),
                close: 19000000 + (index * 10000),
              ),
            ),
          ),
        ],
      ),
    );

    expect(report.historyPointCount, 12);
  });

  test('does not count old cached news as related evidence', () async {
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async {
            expect(messages.single.content, contains('no_sourced_news'));
            return '{"direction":"neutral","scenario_estimate_percent":91,'
                '"summary":"تحلیل با تکیه بر داده فنی و بدون خبر تازه انجام شد.",'
                '"reasons":["خبر تازه و مرتبطی در بازه مجاز وجود ندارد."]}';
          },
    );

    final report = await service.analyze(
      input(newsPublishedAt: DateTime.utc(2026, 8, 1)),
    );

    expect(report.relevantNewsCount, 0);
    expect(report.scenarioEstimatePercent, lessThanOrEqualTo(60));
  });

  test(
    'Iranian assets do not receive the global weekend freshness exception',
    () async {
      final saturday = DateTime.utc(2026, 8, 8, 20);
      expect(saturday.weekday, DateTime.saturday);
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async {
              expect(
                messages.single.content,
                contains('"target_allowed":false'),
              );
              return '{"direction":"upward","scenario_estimate_percent":86,'
                  '"forecast_target_price":19200000,"forecast_target_unit":"IRT",'
                  '"summary":"تاریخچه داخلی برای هدف کوتاه‌مدت تازه نیست.",'
                  '"reasons":["استثنای تعطیلی بازار جهانی برای طلای داخلی اعمال نمی‌شود."]}';
            },
      );

      final report = await service.analyze(
        input(
          symbol: 'GOLD18',
          quoteUnit: 'IRT',
          historyUnit: 'IRT',
          collectedAt: saturday,
          historyStart: DateTime.utc(2026, 8, 7, 4),
        ),
      );

      expect(report.forecastTargetPrice, isNull);
      expect(report.scenarioEstimatePercent, lessThanOrEqualTo(55));
    },
  );

  test('rejects a response in the wrong selected language', () async {
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async =>
              '{"direction":"neutral","scenario_estimate_percent":52,'
              '"summary":"The market evidence is mixed and uncertain today.",'
              '"reasons":["The sourced price and news do not align clearly."]}',
    );

    await expectLater(
      service.analyze(input(language: 'persian')),
      throwsA(
        isA<MarketIntelligenceException>().having(
          (error) => error.code,
          'code',
          'wrong_language',
        ),
      ),
    );
  });

  test(
    'retries a wrong-language response once and accepts the correction',
    () async {
      var calls = 0;
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async {
              calls++;
              if (calls == 1) {
                return '{"direction":"neutral","scenario_estimate_percent":52,'
                    '"summary":"The market evidence is mixed and uncertain today.",'
                    '"reasons":["The sourced price and news do not align clearly."]}';
              }
              expect(messages.single.content, contains('wrong language'));
              return '{"direction":"neutral","scenario_estimate_percent":52,'
                  '"summary":"شواهد منبع‌دار بازار در حال حاضر ترکیبی است.",'
                  '"reasons":["قیمت و خبرها جهت کاملاً یکسانی ندارند."]}';
            },
      );

      final report = await service.analyze(input(language: 'persian'));

      expect(calls, 2);
      expect(report.languageCode, 'persian');
    },
  );

  test('accepts a French report when French is selected', () async {
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async =>
              '{"direction":"neutral","scenario_estimate_percent":54,'
              '"summary":"Les données du marché restent mitigées et incertaines.",'
              '"reasons":["Le prix et les actualités ne donnent pas un signal clair."]}',
    );

    final report = await service.analyze(input(language: 'french'));

    expect(report.languageCode, 'french');
  });

  test('refuses analysis with neither sufficient history nor news', () async {
    final service = MarketIntelligenceService(
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async => '{}',
    );

    await expectLater(
      service.analyze(input(includeNews: false, historyPoints: 0)),
      throwsA(
        isA<MarketIntelligenceException>().having(
          (error) => error.code,
          'code',
          'insufficient_evidence',
        ),
      ),
    );
  });
}
