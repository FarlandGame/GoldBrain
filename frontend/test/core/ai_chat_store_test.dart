import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/ai_chat_store.dart';
import 'package:goldbrain/core/local_persistence_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('recognizes generated chat labels in every supported language', () {
    expect(AiChatStore.generatedConversationTitles, hasLength(8));
    expect(AiChatStore.generatedWelcomeMessages, hasLength(8));
    for (final title in AiChatStore.generatedConversationTitles) {
      expect(AiChatStore.isGeneratedConversationTitle(title), isTrue);
    }
    for (final welcome in AiChatStore.generatedWelcomeMessages) {
      expect(AiChatStore.isGeneratedWelcomeMessage(welcome), isTrue);
    }
    expect(AiChatStore.isGeneratedConversationTitle('Gold outlook'), isFalse);
    expect(AiChatStore.isGeneratedWelcomeMessage('A saved AI answer'), isFalse);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalPersistencePolicy.instance.setSuspended(false);
  });

  test(
    'chat remains memory-only while local persistence is suspended',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final store = AiChatStore.testing();
      await store.load(preferences: preferences);
      LocalPersistencePolicy.instance.setSuspended(true);
      addTearDown(() => LocalPersistencePolicy.instance.setSuspended(false));

      final chat = await store.createConversation(title: 'memory only');
      await store.appendMessage(
        conversationId: chat.id,
        text: 'not persisted',
        fromUser: true,
      );

      expect(store.conversations, hasLength(1));
      expect(preferences.getString('ai_chat.conversations_v1'), isNull);
      expect(preferences.getString('ai_chat.active_id_v1'), isNull);
    },
  );

  test('persists multiple conversations and restores the active one', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = AiChatStore.testing();
    await store.load(preferences: preferences);

    final gold = await store.createConversation(title: 'New conversation');
    await store.appendMessage(
      conversationId: gold.id,
      text: 'تحلیل طلا',
      fromUser: true,
    );
    final silver = await store.createConversation(title: 'New conversation');
    await store.appendMessage(
      conversationId: silver.id,
      text: 'تحلیل نقره',
      fromUser: true,
    );
    await store.selectConversation(gold.id);

    final restored = AiChatStore.testing();
    await restored.load(preferences: preferences);

    expect(restored.conversations, hasLength(2));
    expect(restored.activeConversationId, gold.id);
    expect(restored.activeConversation!.messages.single.text, 'تحلیل طلا');
    expect(
      restored.conversations.map((conversation) => conversation.title),
      containsAll(<String>['تحلیل طلا', 'تحلیل نقره']),
    );
  });

  test('deleting an active conversation selects a remaining chat', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = AiChatStore.testing();
    await store.load(preferences: preferences);
    final first = await store.createConversation(title: 'Gold');
    final second = await store.createConversation(title: 'Silver');

    await store.deleteConversation(second.id);

    expect(store.conversations, hasLength(1));
    expect(store.activeConversationId, first.id);
  });

  test('renames a conversation and persists the custom title', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = AiChatStore.testing();
    await store.load(preferences: preferences);
    final conversation = await store.createConversation(title: 'New chat');

    await store.renameConversation(conversation.id, 'Gold outlook');

    final restored = AiChatStore.testing();
    await restored.load(preferences: preferences);
    expect(restored.activeConversation?.title, 'Gold outlook');
  });

  test('clear all removes persisted chat history', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = AiChatStore.testing();
    await store.load(preferences: preferences);
    await store.createConversation(title: 'Temporary');

    await store.clearAll();
    final restored = AiChatStore.testing();
    await restored.load(preferences: preferences);

    expect(restored.conversations, isEmpty);
    expect(restored.activeConversation, isNull);
  });

  test('keeps persisted history below the storage safety cap', () async {
    final now = DateTime.utc(2026, 8, 10).toIso8601String();
    final largeMessage = List<String>.filled(
      6000,
      String.fromCharCode(0x0634),
    ).join();
    final conversations = List<Map<String, Object>>.generate(24, (index) {
      return <String, Object>{
        'id': 'conversation-$index',
        'title': 'Conversation $index',
        'createdAt': now,
        'updatedAt': now,
        'messages': List<Map<String, Object>>.generate(
          10,
          (messageIndex) => <String, Object>{
            'text': '$largeMessage-$messageIndex',
            'fromUser': messageIndex.isEven,
            'createdAt': now,
          },
        ),
      };
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ai_chat.conversations_v1': jsonEncode(conversations),
      'ai_chat.active_id_v1': 'conversation-0',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = AiChatStore.testing();
    await store.load(preferences: preferences);

    await store.appendMessage(
      conversationId: 'conversation-0',
      text: 'newest message',
      fromUser: true,
    );

    final persisted = preferences.getString('ai_chat.conversations_v1')!;
    expect(utf8.encode(persisted).length, lessThanOrEqualTo(2 * 1024 * 1024));
    expect(store.activeConversationId, 'conversation-0');
    expect(store.activeConversation!.messages.last.text, 'newest message');
  });
}
