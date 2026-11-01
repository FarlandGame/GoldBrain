import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/ai_chat_store.dart';
import 'package:goldbrain/core/gapgpt_service.dart';
import 'package:goldbrain/core/market_intelligence_service.dart';
import 'package:goldbrain/core/market_intelligence_store.dart';
import 'package:goldbrain/screens/ai_assistant_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:goldbrain/widgets/retained_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'actual assistant stream continues across hidden tab and return',
    (tester) async {
      await _setDesktopSurface(tester);
      final stream = StreamController<String>();
      final aiService = _FakeGapGptService(streams: [stream.stream]);
      final chatStore = AiChatStore.testing();
      final intelligence = _TestIntelligenceHarness();
      final active = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: active,
              builder: (context, value, _) => RetainedTab(
                active: value,
                retainedChild: AiAssistantScreen(
                  key: const ValueKey('retained-assistant'),
                  palette: themePalettes[GoldBrainTheme.gold]!,
                  selectedLanguage: GoldBrainLanguage.persian,
                  aiService: aiService,
                  chatStore: chatStore,
                  intelligenceStore: intelligence.store,
                ),
                otherChild: const Text('Other tab'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _send(tester, 'سلام');
      stream.add('این پاسخ');
      await tester.pump();
      active.value = false;
      await tester.pump();
      expect(find.text('Other tab'), findsOneWidget);
      expect(stream.hasListener, isTrue);
      stream.add(' هنگام تغییر تب هم ادامه دارد.');
      await stream.close();
      await tester.pump();
      expect(
        chatStore.activeConversation!.messages
            .where((m) => m.text.contains('هنگام تغییر تب'))
            .length,
        1,
      );
      active.value = true;
      await tester.pumpAndSettle();
      expect(find.textContaining('هنگام تغییر تب'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).enabled,
        isTrue,
      );
      expect(aiService.streamCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      active.dispose();
      intelligence.dispose();
      aiService.close();
    },
  );

  testWidgets('changing language invalidates an in-flight stream safely', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final stream = StreamController<String>();
    final aiService = _FakeGapGptService(
      streams: <Stream<String>>[stream.stream],
    );
    final chatStore = AiChatStore.testing();
    final intelligence = _TestIntelligenceHarness();

    await tester.pumpWidget(
      _host(
        language: GoldBrainLanguage.persian,
        aiService: aiService,
        chatStore: chatStore,
        intelligenceStore: intelligence.store,
      ),
    );
    await tester.pumpAndSettle();
    await _send(tester, 'قیمت طلا را توضیح بده');
    expect(aiService.streamCalls, 1);

    stream.add('این پاسخ قدیمی هنوز در حال دریافت است.');
    await tester.pump();
    expect(find.textContaining('پاسخ قدیمی'), findsOneWidget);

    await tester.pumpWidget(
      _host(
        language: GoldBrainLanguage.english,
        aiService: aiService,
        chatStore: chatStore,
        intelligenceStore: intelligence.store,
      ),
    );
    await tester.pump();
    expect(stream.hasListener, isFalse);
    stream.add(' این بخش نباید نوشته یا ذخیره شود.');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('پاسخ قدیمی'), findsNothing);
    final storedText = chatStore.activeConversation!.messages
        .map((message) => message.text)
        .join('\n');
    expect(storedText, isNot(contains('پاسخ قدیمی')));
    expect(storedText, contains('قیمت طلا'));
    unawaited(stream.close());
    await tester.pumpWidget(const SizedBox.shrink());
    intelligence.dispose();
    aiService.close();
  });

  testWidgets('wrong-language streamed answer is repaired before persistence', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final stream = StreamController<String>();
    final repair = Completer<String>();
    final aiService = _FakeGapGptService(
      streams: <Stream<String>>[stream.stream],
      repair: repair,
    );
    final chatStore = AiChatStore.testing();
    final intelligence = _TestIntelligenceHarness();

    await tester.pumpWidget(
      _host(
        language: GoldBrainLanguage.persian,
        aiService: aiService,
        chatStore: chatStore,
        intelligenceStore: intelligence.store,
      ),
    );
    await tester.pumpAndSettle();
    await _send(tester, 'بازار را خلاصه کن');

    const wrong =
        'The sourced market evidence is mixed and needs more confirmation.';
    stream.add(wrong);
    await tester.pump();
    expect(find.textContaining('sourced market evidence'), findsOneWidget);
    await stream.close();
    await tester.pump();
    expect(aiService.repairCalls, 1);
    expect(aiService.lastRepairSystemPrompt, contains('Persian (Farsi)'));

    const repaired =
        'شواهد منبع‌دار بازار ترکیبی است و برای نتیجه‌گیری به تأیید بیشتری نیاز دارد.';
    repair.complete(repaired);
    await tester.pumpAndSettle();

    expect(find.textContaining('شواهد منبع‌دار'), findsOneWidget);
    expect(find.textContaining('sourced market evidence'), findsNothing);
    final assistantMessages = chatStore.activeConversation!.messages
        .where((message) => !message.fromUser)
        .map((message) => message.text)
        .toList();
    expect(assistantMessages, contains(repaired));
    expect(assistantMessages, isNot(contains(wrong)));
    await tester.pumpWidget(const SizedBox.shrink());
    intelligence.dispose();
    aiService.close();
  });

  testWidgets(
    'RTL conversation rename owns its controller through route disposal',
    (tester) async {
      await _setDesktopSurface(tester);
      final aiService = _FakeGapGptService(streams: const <Stream<String>>[]);
      final chatStore = AiChatStore.testing();
      final intelligence = _TestIntelligenceHarness();

      await tester.pumpWidget(
        _host(
          language: GoldBrainLanguage.persian,
          aiService: aiService,
          chatStore: chatStore,
          intelligenceStore: intelligence.store,
        ),
      );
      await tester.pumpAndSettle();
      final conversationId = chatStore.activeConversation!.id;

      Future<void> renameTo(String value) async {
        await tester.tap(
          find.byKey(ValueKey<String>('rename-conversation-$conversationId')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('rename-conversation-field')),
          value,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('rename-conversation-save')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(chatStore.activeConversation!.title, value);
        expect(find.text(value), findsOneWidget);
      }

      await renameTo('یاهو');
      await renameTo('تحلیل بازار طلا');
      await renameTo('یاهو');

      // Exercise selection/navigation and deletion after repeated dialog route
      // transitions; this is where the old disposed controller asserted.
      await chatStore.createConversation(title: 'گفت‌وگوی دوم');
      await tester.pumpAndSettle();
      await tester.tap(find.text('یاهو'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(ValueKey<String>('delete-conversation-$conversationId')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        chatStore.conversations.any((item) => item.id == conversationId),
        isFalse,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      intelligence.dispose();
      aiService.close();
    },
  );

  testWidgets('connection badge is honest before and after a real response', (
    tester,
  ) async {
    await _setDesktopSurface(tester);
    final aiService = _FakeGapGptService(
      streams: <Stream<String>>[Stream<String>.value('پاسخ فارسی معتبر')],
    );
    final chatStore = AiChatStore.testing();
    final intelligence = _TestIntelligenceHarness();

    await tester.pumpWidget(
      _host(
        language: GoldBrainLanguage.persian,
        aiService: aiService,
        chatStore: chatStore,
        intelligenceStore: intelligence.store,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('اتصال هنوز آزموده نشده'), findsWidgets);
    expect(find.text('متصل'), findsNothing);

    await _send(tester, 'سلام');
    await tester.pumpAndSettle();
    expect(find.text('متصل'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    intelligence.dispose();
    aiService.close();
  });
}

Future<void> _setDesktopSurface(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _host({
  required GoldBrainLanguage language,
  required GapGptService aiService,
  required AiChatStore chatStore,
  required MarketIntelligenceStore intelligenceStore,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AiAssistantScreen(
        key: const ValueKey('assistant-under-test'),
        palette: themePalettes[GoldBrainTheme.gold]!,
        selectedLanguage: language,
        aiService: aiService,
        chatStore: chatStore,
        intelligenceStore: intelligenceStore,
      ),
    ),
  );
}

Future<void> _send(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextField).last, value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

class _FakeGapGptService extends GapGptService {
  _FakeGapGptService({required this.streams, this.repair})
    : super(apiKey: 'test-key');

  final List<Stream<String>> streams;
  final Completer<String>? repair;
  int streamCalls = 0;
  int repairCalls = 0;
  String? lastRepairSystemPrompt;

  @override
  Stream<String> createChatCompletionStream({
    required List<AiChatMessage> messages,
    required String systemPrompt,
    double temperature = 0.35,
    Map<String, Object?>? responseFormat,
  }) {
    final index = streamCalls++;
    return streams[index];
  }

  @override
  Future<String> createChatCompletion({
    required List<AiChatMessage> messages,
    required String systemPrompt,
    double temperature = 0.35,
    Map<String, Object?>? responseFormat,
  }) {
    repairCalls++;
    lastRepairSystemPrompt = systemPrompt;
    return repair?.future ?? Future<String>.value(messages.last.content);
  }
}

class _TestIntelligenceHarness {
  _TestIntelligenceHarness()
    : service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async => '{"reports":[]}',
      ) {
    store = MarketIntelligenceStore(
      service: service,
      inputLoader: (languageCode) async => MarketIntelligenceInput(
        languageCode: languageCode,
        quotes: const <IntelligenceQuoteEvidence>[],
        news: const <IntelligenceNewsEvidence>[],
        collectedAt: DateTime.utc(2026, 8, 11),
      ),
    );
  }

  final MarketIntelligenceService service;
  late final MarketIntelligenceStore store;

  void dispose() {
    store.dispose();
    service.close();
  }
}
