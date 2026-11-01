import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_persistence_policy.dart';

class StoredAiMessage {
  const StoredAiMessage({
    required this.text,
    required this.fromUser,
    required this.createdAt,
  });

  final String text;
  final bool fromUser;
  final DateTime createdAt;

  Map<String, Object> toJson() => <String, Object>{
    'text': text,
    'fromUser': fromUser,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static StoredAiMessage? fromJson(Object? value) {
    if (value is! Map) return null;
    final text = value['text'];
    final fromUser = value['fromUser'];
    final createdAt = DateTime.tryParse(value['createdAt']?.toString() ?? '');
    if (text is! String ||
        text.trim().isEmpty ||
        fromUser is! bool ||
        createdAt == null) {
      return null;
    }
    return StoredAiMessage(
      text: _boundedText(text),
      fromUser: fromUser,
      createdAt: createdAt.toUtc(),
    );
  }
}

class AiConversation {
  const AiConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<StoredAiMessage> messages;

  AiConversation copyWith({
    String? title,
    DateTime? updatedAt,
    List<StoredAiMessage>? messages,
  }) {
    return AiConversation(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'title': title,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'messages': messages.map((message) => message.toJson()).toList(),
  };

  static AiConversation? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    final createdAt = DateTime.tryParse(value['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(value['updatedAt']?.toString() ?? '');
    if (id is! String ||
        id.trim().isEmpty ||
        title is! String ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    final rawMessages = value['messages'];
    final messages = rawMessages is List
        ? rawMessages
              .map(StoredAiMessage.fromJson)
              .whereType<StoredAiMessage>()
              .take(AiChatStore.maximumMessagesPerConversation)
              .toList(growable: false)
        : const <StoredAiMessage>[];
    return AiConversation(
      id: id,
      title: _boundedTitle(title),
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      messages: messages,
    );
  }
}

class AiChatStore extends ChangeNotifier {
  AiChatStore._();

  @visibleForTesting
  AiChatStore.testing();

  static final AiChatStore instance = AiChatStore._();

  static const maximumConversations = 24;
  static const maximumMessagesPerConversation = 80;
  static const maximumStorageBytes = 2 * 1024 * 1024;
  static const _storageKey = 'ai_chat.conversations_v1';
  static const _activeIdKey = 'ai_chat.active_id_v1';

  /// Generated labels are localized at display time. This keeps an old
  /// Persian/English default title or greeting from leaking into the UI after
  /// the user changes the application language, while preserving real chat
  /// messages exactly as they were written.
  static const generatedConversationTitles = <String>{
    'New conversation',
    'گفت‌وگوی جدید',
    '新しい会話',
    'Новый диалог',
    '新对话',
    'محادثة جديدة',
    'Yeni sohbet',
    'Nouvelle conversation',
  };

  static const generatedWelcomeMessages = <String>{
    'Hello, I am GoldBrain. Ask me about this application, sourced market prices, gold, currencies, or financial news.',
    'سلام، من GoldBrain هستم. درباره خود برنامه، قیمت‌های منبع‌دار بازار، طلا، ارز یا اخبار مالی از من بپرسید.',
    'こんにちは、GoldBrainです。このアプリ、出典付き市場価格、金、通貨、金融ニュースについて質問してください。',
    'Здравствуйте, я GoldBrain. Спросите о приложении, рыночных ценах с источниками, золоте, валютах или финансовых новостях.',
    '你好，我是 GoldBrain。你可以询问本应用、带来源的市场价格、黄金、货币或财经新闻。',
    'مرحبًا، أنا GoldBrain. اسألني عن التطبيق والأسعار الموثقة والذهب والعملات والأخبار المالية.',
    'Merhaba, ben GoldBrain. Uygulama, kaynaklı fiyatlar, altın, döviz veya finans haberlerini sorabilirsiniz.',
    'Bonjour, je suis GoldBrain. Interrogez-moi sur l’application, les prix sourcés, l’or, les devises ou l’actualité financière.',
  };

  static bool isGeneratedConversationTitle(String value) =>
      generatedConversationTitles.contains(value.trim());

  static bool isGeneratedWelcomeMessage(String value) =>
      generatedWelcomeMessages.contains(value.trim());

  SharedPreferences? _preferences;
  List<AiConversation> _conversations = const [];
  String? _activeConversationId;
  bool _loaded = false;
  int _idSequence = 0;

  bool get loaded => _loaded;
  List<AiConversation> get conversations => List.unmodifiable(_conversations);
  String? get activeConversationId => _activeConversationId;

  AiConversation? get activeConversation {
    final activeId = _activeConversationId;
    if (activeId == null) return null;
    for (final conversation in _conversations) {
      if (conversation.id == activeId) return conversation;
    }
    return null;
  }

  Future<void> load({SharedPreferences? preferences}) async {
    if (_loaded && preferences == null) return;
    _preferences = preferences ?? await SharedPreferences.getInstance();
    final raw = _preferences!.getString(_storageKey);
    final parsed = <AiConversation>[];
    if (raw != null && raw.length <= 2 * 1024 * 1024) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          parsed.addAll(decoded.map(AiConversation.fromJson).whereType());
        }
      } on FormatException {
        // Corrupt local history is ignored instead of blocking the assistant.
      }
    }
    parsed.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _conversations = parsed.take(maximumConversations).toList(growable: false);
    final storedActiveId = _preferences!.getString(_activeIdKey);
    _activeConversationId =
        _conversations.any((conversation) => conversation.id == storedActiveId)
        ? storedActiveId
        : _conversations.firstOrNull?.id;
    _loaded = true;
    notifyListeners();
  }

  Future<AiConversation> createConversation({required String title}) async {
    await _ensureLoaded();
    final now = DateTime.now().toUtc();
    final conversation = AiConversation(
      id: '${now.microsecondsSinceEpoch}-${_idSequence++}',
      title: _boundedTitle(title),
      createdAt: now,
      updatedAt: now,
      messages: const [],
    );
    _conversations = <AiConversation>[
      conversation,
      ..._conversations,
    ].take(maximumConversations).toList(growable: false);
    _activeConversationId = conversation.id;
    await _persist();
    notifyListeners();
    return conversation;
  }

  Future<void> selectConversation(String id) async {
    await _ensureLoaded();
    if (!_conversations.any((conversation) => conversation.id == id)) return;
    _activeConversationId = id;
    if (LocalPersistencePolicy.instance.canWrite) {
      await _preferences!.setString(_activeIdKey, id);
    }
    notifyListeners();
  }

  Future<void> renameConversation(String id, String title) async {
    await _ensureLoaded();
    final normalized = _boundedTitle(title);
    final index = _conversations.indexWhere(
      (conversation) => conversation.id == id,
    );
    if (index < 0 || normalized == _conversations[index].title) return;
    final current = _conversations[index];
    final next = [..._conversations];
    next[index] = current.copyWith(title: normalized);
    _conversations = List<AiConversation>.unmodifiable(next);
    await _persist();
    notifyListeners();
  }

  Future<void> appendMessage({
    required String conversationId,
    required String text,
    required bool fromUser,
  }) async {
    await _ensureLoaded();
    final normalized = _boundedText(text).trim();
    if (normalized.isEmpty) return;
    final index = _conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index < 0) return;

    final current = _conversations[index];
    final now = DateTime.now().toUtc();
    final messages = <StoredAiMessage>[
      ...current.messages,
      StoredAiMessage(text: normalized, fromUser: fromUser, createdAt: now),
    ];
    final autoTitle = fromUser && !current.messages.any((item) => item.fromUser)
        ? _titleFromFirstMessage(normalized)
        : current.title;
    final updated = current.copyWith(
      title: autoTitle,
      updatedAt: now,
      messages: messages.length <= maximumMessagesPerConversation
          ? List.unmodifiable(messages)
          : List.unmodifiable(
              messages.sublist(
                messages.length - maximumMessagesPerConversation,
              ),
            ),
    );
    _replaceAndPromote(index, updated);
    await _persist();
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    await _ensureLoaded();
    _conversations = _conversations
        .where((conversation) => conversation.id != id)
        .toList(growable: false);
    if (_activeConversationId == id) {
      _activeConversationId = _conversations.firstOrNull?.id;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _ensureLoaded();
    _conversations = const [];
    _activeConversationId = null;
    await Future.wait([
      _preferences!.remove(_storageKey),
      _preferences!.remove(_activeIdKey),
    ]);
    notifyListeners();
  }

  void _replaceAndPromote(int index, AiConversation updated) {
    final next = [..._conversations]..removeAt(index);
    _conversations = <AiConversation>[
      updated,
      ...next,
    ].take(maximumConversations).toList(growable: false);
    _activeConversationId = updated.id;
  }

  Future<void> _persist() async {
    if (!LocalPersistencePolicy.instance.canWrite) return;
    var retained = _conversations;
    var encoded = _encodeConversations(retained);
    while (utf8.encode(encoded).length > maximumStorageBytes &&
        retained.isNotEmpty) {
      final oldest = retained.last;
      if (oldest.messages.length > 1) {
        retained = <AiConversation>[
          ...retained.take(retained.length - 1),
          oldest.copyWith(messages: oldest.messages.sublist(1)),
        ];
      } else if (retained.length > 1) {
        retained = retained.take(retained.length - 1).toList(growable: false);
      } else {
        // A single bounded message is always comfortably below the cap.
        break;
      }
      encoded = _encodeConversations(retained);
    }
    if (!identical(retained, _conversations)) {
      _conversations = List<AiConversation>.unmodifiable(retained);
      if (!_conversations.any(
        (conversation) => conversation.id == _activeConversationId,
      )) {
        _activeConversationId = _conversations.firstOrNull?.id;
      }
    }
    await Future.wait([
      _preferences!.setString(_storageKey, encoded),
      if (_activeConversationId case final activeId?)
        _preferences!.setString(_activeIdKey, activeId)
      else
        _preferences!.remove(_activeIdKey),
    ]);
  }

  String _encodeConversations(List<AiConversation> conversations) => jsonEncode(
    conversations.map((conversation) => conversation.toJson()).toList(),
  );

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }
}

String _boundedText(String value) {
  const maximumLength = 20000;
  final normalized = value.replaceAll('\u0000', '');
  return normalized.length <= maximumLength
      ? normalized
      : normalized.substring(0, maximumLength);
}

String _boundedTitle(String value) {
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return 'New conversation';
  return normalized.length <= 48
      ? normalized
      : '${normalized.substring(0, 47)}…';
}

String _titleFromFirstMessage(String value) => _boundedTitle(value);
