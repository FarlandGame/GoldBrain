import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/gapgpt_service.dart';
import 'package:goldbrain/core/goldbrain_ai_policy.dart';

void main() {
  test('requires every supported response language explicitly', () {
    for (final entry in GoldBrainAiPolicy.languageNames.entries) {
      final prompt = GoldBrainAiPolicy.baseSystemPrompt(
        languageCode: entry.key,
        tone: 'balanced',
      );
      expect(prompt, contains('Write the entire answer in ${entry.value}'));
      expect(prompt, contains('Do not switch to English'));
    }
  });

  test('keeps financial specialization without blocking general tasks', () {
    final prompt = GoldBrainAiPolicy.baseSystemPrompt(
      languageCode: 'persian',
      tone: 'detailed',
    );

    expect(prompt, contains('specialization in gold'));
    expect(prompt, contains('rewriting'));
    expect(prompt, contains('proofreading'));
    expect(prompt, contains('outside finance'));
  });

  test('attaches market context only to relevant questions', () {
    expect(
      GoldBrainAiPolicy.requiresMarketContext('قیمت طلا امروز چیست؟'),
      isTrue,
    );
    expect(
      GoldBrainAiPolicy.requiresMarketContext('Rewrite this paragraph clearly'),
      isFalse,
    );
  });

  test('validates assistant responses for every supported language', () {
    const samples = <String, String>{
      'english': 'The sourced market evidence supports a cautious scenario.',
      'persian': 'این پاسخ بر اساس شواهد معتبر بازار نوشته شده است.',
      'japanese': 'この回答は検証済みの市場情報に基づいています。',
      'russian': 'Этот ответ основан на проверенных рыночных данных.',
      'chinese': '此回答基于经过验证的市场数据和可靠信息。',
      'arabic': 'تستند هذه الإجابة إلى بيانات السوق الموثوقة والمصادر المتاحة.',
      'turkish':
          'Bu yanıt doğrulanmış piyasa verileri ve kaynaklar ile hazırlanmıştır.',
      'french': 'Cette réponse est fondée sur les données vérifiées du marché.',
    };
    for (final entry in samples.entries) {
      expect(
        GoldBrainAiPolicy.isExpectedResponseLanguage(entry.value, entry.key),
        isTrue,
        reason: entry.key,
      );
    }
    expect(
      GoldBrainAiPolicy.isExpectedResponseLanguage(
        samples['persian']!,
        'english',
      ),
      isFalse,
    );
  });

  test('removes old-language assistant history but keeps user messages', () {
    final filtered = GoldBrainAiPolicy.historyForLanguage(const <AiChatMessage>[
      AiChatMessage(role: 'user', content: 'قیمت طلا چقدر است؟'),
      AiChatMessage(
        role: 'assistant',
        content: 'این پاسخ قدیمی به زبان فارسی نوشته شده است.',
      ),
      AiChatMessage(
        role: 'assistant',
        content: 'This current answer is written in English for the user.',
      ),
    ], 'english');

    expect(filtered, hasLength(2));
    expect(filtered.first.role, 'user');
    expect(filtered.first.content, contains('طلا'));
    expect(filtered.last.content, contains('English'));
  });
}
