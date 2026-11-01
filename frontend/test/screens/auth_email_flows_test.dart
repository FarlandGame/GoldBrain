import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/backend_api_client.dart';
import 'package:goldbrain/core/backend_connection.dart';
import 'package:goldbrain/core/backend_session.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:goldbrain/screens/auth_screen.dart';
import 'package:goldbrain/screens/dashboard_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault implements RefreshTokenVault {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String token) async => this.token = token;
  @override
  Future<void> delete() async => token = null;
}

http.Response _challenge({int expiry = 900, int resend = 60}) => http.Response(
  jsonEncode({'accepted': true, 'expires_in': expiry, 'resend_after': resend}),
  200,
);

http.Response _error(String code, int status, {int? retry}) => http.Response(
  jsonEncode({
    'detail': {'code': code, 'message': 'Server message'},
  }),
  status,
  headers: {if (retry != null) 'retry-after': '$retry'},
);

Future<BackendConnection> _open(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  Size size = const Size(1200, 900),
  GoldBrainLanguage language = GoldBrainLanguage.english,
}) async {
  SharedPreferences.setMockInitialValues({
    'settings.motion_enabled': false,
    'settings.reduced_motion': true,
    'settings.sound_enabled': false,
    'settings.music_enabled': false,
  });
  await SettingsStore.instance.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final connection = BackendConnection(
    api: GoldBrainBackendClient(
      config: GoldBrainBackendConfig(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        apiKey: '',
      ),
      client: MockClient(handler),
    ),
    vault: _Vault(),
  );
  addTearDown(connection.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: AuthScreen(
        selectedTheme: GoldBrainTheme.gold,
        selectedLanguage: language,
        connection: connection,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return connection;
}

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

Future<void> _enterText(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _requestReset(WidgetTester tester) async {
  await _tap(tester, 'auth-forgot-password');
  await _enterText(tester, _field('auth-reset-email'), 'alice@example.com');
  await _tap(tester, 'auth-email-submit');
}

void main() {
  for (final language in [
    GoldBrainLanguage.english,
    GoldBrainLanguage.persian,
  ]) {
    final persian = language == GoldBrainLanguage.persian;
    final size = persian ? const Size(520, 360) : const Size(1200, 900);
    final mismatch = persian
        ? 'رمز عبور و تکرار آن یکسان نیستند.'
        : 'Passwords do not match.';
    final requiredConfirmation = persian
        ? 'رمز عبور را دوباره وارد کنید.'
        : 'Please re-enter your password.';
    testWidgets('signup confirms exact passwords in $language at $size', (
      tester,
    ) async {
      final requests = <String>[];
      await _open(
        tester,
        (request) async {
          requests.add(request.url.path);
          expect(request.url.path, '/api/v1/auth/register');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['password'], 'Password1234');
          expect(body.containsKey('confirm_password'), isFalse);
          return http.Response(
            jsonEncode({
              'email': 'alice@example.com',
              'verification_required': true,
              'expires_in': 900,
              'resend_after': 60,
            }),
            201,
          );
        },
        size: size,
        language: language,
      );
      expect(find.byKey(const Key('auth-password-confirm')), findsNothing);
      await _tap(tester, 'auth-switch-mode');
      await tester.pumpAndSettle();
      await _enterText(tester, _field('auth-name'), 'Alice');
      await _enterText(tester, _field('auth-email'), 'alice@example.com');
      await _enterText(tester, _field('auth-password'), 'Password1234');
      final submit = find.byKey(const Key('auth-submit'));
      final confirm = _field('auth-password-confirm');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await _enterText(tester, confirm, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text(requiredConfirmation), findsOneWidget);
      expect(requests, isEmpty);
      await _enterText(tester, confirm, 'Password1234 ');
      expect(find.text(mismatch), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(requests, isEmpty);
      await _enterText(tester, confirm, 'Password1234');
      expect(find.text(mismatch), findsNothing);
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await _enterText(tester, _field('auth-password'), 'Different1234');
      expect(find.text(mismatch), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await _enterText(tester, _field('auth-password'), 'Password1234');
      final primary = tester.widget<TextField>(_field('auth-password'));
      final repeated = tester.widget<TextField>(confirm);
      expect(repeated.obscureText, isTrue);
      expect(repeated.style, primary.style);
      expect(repeated.decoration!.fillColor, primary.decoration!.fillColor);
      expect(
        repeated.decoration!.enabledBorder,
        primary.decoration!.enabledBorder,
      );
      final primaryRect = tester.getRect(_field('auth-password'));
      final confirmRect = tester.getRect(confirm);
      if (persian) {
        expect(confirmRect.top, greaterThan(primaryRect.bottom));
      } else {
        expect(confirmRect.top, primaryRect.top);
        expect(confirmRect.left, greaterThan(primaryRect.right));
      }
      expect(tester.takeException(), isNull);
      await _tap(tester, 'auth-submit');
      expect(requests, ['/api/v1/auth/register']);
      expect(
        tester
            .widget<TextField>(_field('auth-new-password-confirm'))
            .controller!
            .text,
        'Password1234',
      );
      await _tap(tester, 'auth-back-to-login');
      await _tap(tester, 'auth-switch-mode');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(confirm).controller!.text, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'reset blocks mismatched passwords and accepts a corrected pair in $language',
      (tester) async {
        final requests = <String>[];
        await _open(
          tester,
          (request) async {
            requests.add(request.url.path);
            if (request.url.path.endsWith('/request')) return _challenge();
            expect(jsonDecode(request.body), {
              'email': 'alice@example.com',
              'code': '123456',
              'new_password': 'ChangedPassword1234',
            });
            return http.Response('', 204);
          },
          size: size,
          language: language,
        );
        await _requestReset(tester);
        await _enterText(tester, _field('auth-email-code'), '123456');
        await _enterText(
          tester,
          _field('auth-new-password'),
          'ChangedPassword1234',
        );
        final submit = find.byKey(const Key('auth-email-submit'));
        final confirm = _field('auth-new-password-confirm');
        expect(tester.widget<FilledButton>(submit).onPressed, isNull);
        await _enterText(tester, confirm, '');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(find.text(requiredConfirmation), findsOneWidget);
        expect(requests, ['/api/v1/auth/password-reset/request']);
        await _enterText(tester, confirm, 'WrongPassword1234');
        expect(find.text(mismatch), findsOneWidget);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(requests, ['/api/v1/auth/password-reset/request']);
        expect(tester.widget<FilledButton>(submit).onPressed, isNull);
        await _enterText(tester, confirm, 'ChangedPassword1234');
        expect(find.text(mismatch), findsNothing);
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        expect(tester.widget<TextField>(confirm).obscureText, isTrue);
        expect(tester.takeException(), isNull);
        await _tap(tester, 'auth-email-submit');
        expect(requests, [
          '/api/v1/auth/password-reset/request',
          '/api/v1/auth/password-reset/confirm',
        ]);
        expect(
          find.byKey(const Key('auth-new-password-confirm')),
          findsNothing,
        );
        await _requestReset(tester);
        expect(tester.widget<TextField>(confirm).controller!.text, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final deliveryFails in [false, true]) {
    testWidgets(
      'signup stays in verification after ${deliveryFails ? 'delivery failure' : 'pending response'}',
      (tester) async {
        final paths = <String>[];
        final connection = await _open(tester, (request) async {
          paths.add(request.url.path);
          expect(request.url.path, '/api/v1/auth/register');
          if (deliveryFails) return _error('email_delivery_failed', 503);
          return http.Response(
            jsonEncode({
              'email': 'alice@example.com',
              'verification_required': true,
              'expires_in': 900,
              'resend_after': 60,
            }),
            201,
          );
        });
        await _tap(tester, 'auth-switch-mode');
        await tester.pumpAndSettle();
        expect(find.text('Create your account'), findsOneWidget);
        await _enterText(tester, _field('auth-name'), 'Alice');
        await _enterText(tester, _field('auth-email'), 'alice@example.com');
        await _enterText(tester, _field('auth-password'), 'Password1234');
        await _enterText(
          tester,
          _field('auth-password-confirm'),
          'Password1234',
        );
        await _tap(tester, 'auth-submit');
        expect(find.text('Verify your email'), findsOneWidget);
        expect(find.text('alice@example.com'), findsOneWidget);
        expect(
          find.text(
            "Check your Spam/Junk folder if you don't see the email within a minute.",
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextField>(_field('auth-new-password'))
              .controller!
              .text,
          'Password1234',
        );
        expect(find.byType(DashboardScreen), findsNothing);
        expect(connection.session.authenticated, isFalse);
        expect(paths, ['/api/v1/auth/register']);
        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('auth-resend-code')))
              .onPressed,
          deliveryFails ? isNotNull : isNull,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, 'auth-back-to-login');
        expect(
          tester.widget<TextField>(_field('auth-password')).controller!.text,
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'pending login uses verification panel, locks resend, and never opens markets',
    (tester) async {
      final paths = <String>[];
      final connection = await _open(tester, (request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/login'))
          return _error('email_verification_required', 403);
        if (request.url.path.endsWith('/request')) {
          return http.Response(
            jsonEncode({
              'accepted': true,
              'email': 'alice@example.com',
              'expires_in': 900,
              'resend_after': 60,
            }),
            200,
          );
        }
        expect(jsonDecode(request.body)['code'], '123456');
        expect(jsonDecode(request.body)['new_password'], 'Password1234');
        return _error('otp_invalid', 422);
      });
      await _enterText(tester, _field('auth-email'), 'alice@example.com');
      await _enterText(tester, _field('auth-password'), 'Password1234');
      await _tap(tester, 'auth-submit');
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
      expect(find.text('Continue as guest (local only)'), findsNothing);
      expect(connection.session.authenticated, isFalse);
      await _tap(tester, 'auth-resend-code');
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('auth-resend-code')))
            .onPressed,
        isNull,
      );
      await _enterText(tester, _field('auth-email-code'), '۱۲٣۴٥۶');
      await _enterText(tester, _field('auth-new-password'), 'Password1234');
      await _enterText(
        tester,
        _field('auth-new-password-confirm'),
        'Password1234',
      );
      await _tap(tester, 'auth-email-submit');
      expect(
        find.text(
          'The code is incorrect or no longer valid. Check it or request a new one.',
        ),
        findsOneWidget,
      );
      expect(connection.session.authenticated, isFalse);
      expect(paths.last, '/api/v1/auth/email-verification/confirm');
      await _tap(tester, 'auth-back-to-login');
      expect(find.text('Welcome back'), findsOneWidget);
      expect(
        tester.widget<TextField>(_field('auth-password')).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'verification resend unlocks at 60 seconds while the 15 minute code stays valid',
    (tester) async {
      var sentRequests = 0;
      await _open(tester, (request) async {
        if (request.url.path.endsWith('/login')) {
          return _error('email_verification_required', 403);
        }
        expect(request.url.path, '/api/v1/auth/email-verification/request');
        sentRequests++;
        return _challenge();
      });
      await _enterText(tester, _field('auth-email'), 'alice@example.com');
      await _enterText(tester, _field('auth-password'), 'Password1234');
      await _tap(tester, 'auth-submit');
      await _tap(tester, 'auth-resend-code');
      final resend = find.byKey(const Key('auth-resend-code'));
      await _enterText(
        tester,
        _field('auth-new-password-confirm'),
        'Password1234',
      );
      expect(
        find.text('Code validity (minutes:seconds): 15:00.'),
        findsOneWidget,
      );
      expect(find.text('Resend code in 60 seconds'), findsOneWidget);
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      await tester.pump(const Duration(seconds: 59));
      expect(find.text('Resend code in 1 seconds'), findsOneWidget);
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<TextButton>(resend).onPressed, isNotNull);
      expect(
        find.text('Code validity (minutes:seconds): 14:00.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('auth-email-submit')))
            .onPressed,
        isNotNull,
      );
      expect(sentRequests, 1);
      await _tap(tester, 'auth-resend-code');
      expect(sentRequests, 2);
      expect(find.text('Resend code in 60 seconds'), findsOneWidget);
      expect(
        find.text('Code validity (minutes:seconds): 15:00.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'reset completion posts email/code/new password and returns to sign in',
    (tester) async {
      final paths = <String>[];
      final connection = await _open(tester, (request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/request')) return _challenge();
        expect(jsonDecode(request.body), {
          'email': 'alice@example.com',
          'code': '123456',
          'new_password': 'ChangedPassword1234',
        });
        return http.Response('', 204);
      });
      await _requestReset(tester);
      expect(find.text('Reset your password'), findsOneWidget);
      await _enterText(tester, _field('auth-email-code'), '123456');
      await _enterText(
        tester,
        _field('auth-new-password'),
        'ChangedPassword1234',
      );
      await _enterText(
        tester,
        _field('auth-new-password-confirm'),
        'ChangedPassword1234',
      );
      await _tap(tester, 'auth-email-submit');
      expect(
        find.text('Password updated. Sign in with your new password.'),
        findsOneWidget,
      );
      expect(find.text('Welcome back'), findsOneWidget);
      expect(paths, [
        '/api/v1/auth/password-reset/request',
        '/api/v1/auth/password-reset/confirm',
      ]);
      expect(connection.session.authenticated, isFalse);
      expect(
        tester.widget<TextField>(_field('auth-password')).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'delivery failure and expired reset are retryable with server cooldown',
    (tester) async {
      var requests = 0;
      await _open(tester, (request) async {
        if (request.url.path.endsWith('/request')) {
          requests++;
          if (requests == 1) return _error('email_delivery_failed', 503);
          if (requests == 3) return _error('otp_resend_limited', 429, retry: 2);
          return _challenge(resend: 0);
        }
        return _error('otp_expired', 422);
      });
      await _requestReset(tester);
      expect(
        find.text(
          'The email could not be sent. Please try sending the code again.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('auth-reset-email')), findsOneWidget);
      await _tap(tester, 'auth-email-submit');
      await _enterText(tester, _field('auth-email-code'), '123456');
      await _enterText(
        tester,
        _field('auth-new-password'),
        'ChangedPassword1234',
      );
      await _enterText(
        tester,
        _field('auth-new-password-confirm'),
        'ChangedPassword1234',
      );
      await _tap(tester, 'auth-email-submit');
      expect(
        find.text('This code has expired. Request a new code.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('auth-email-submit')))
            .onPressed,
        isNull,
      );
      await _tap(tester, 'auth-resend-code');
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('auth-resend-code')))
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('auth-resend-code')))
            .onPressed,
        isNotNull,
      );
      await _tap(tester, 'auth-resend-code');
      expect(
        tester.widget<TextField>(_field('auth-email-code')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(_field('auth-new-password')).controller!.text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(_field('auth-new-password-confirm'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('auth-email-submit')))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(520, 900),
    const Size(520, 360),
    const Size(915, 412),
    const Size(1200, 760),
  ]) {
    testWidgets(
      'reset form preserves RTL layout and styles at ${size.width}x${size.height}',
      (tester) async {
        await _open(
          tester,
          (_) async => _challenge(expiry: 2, resend: 1),
          size: size,
          language: GoldBrainLanguage.persian,
        );
        await _requestReset(tester);
        expect(find.text('بازیابی رمز عبور'), findsOneWidget);
        expect(
          find.text(
            'اگر تا یک دقیقه ایمیل را ندیدید، پوشهٔ Spam/Junk (هرزنامه) را بررسی کنید.',
          ),
          findsOneWidget,
        );
        expect(
          Directionality.of(tester.element(_field('auth-email-code'))),
          TextDirection.rtl,
        );
        expect(
          tester.widget<TextField>(_field('auth-new-password')).obscureText,
          isTrue,
        );
        expect(
          tester
              .widget<TextField>(_field('auth-new-password-confirm'))
              .obscureText,
          isTrue,
        );
        final button = tester.widget<FilledButton>(
          find.byKey(const Key('auth-email-submit')),
        );
        expect(
          button.style!.backgroundColor!.resolve({}),
          themePalettes[GoldBrainTheme.gold]!.primary,
        );
        await tester.pump(const Duration(seconds: 2));
        expect(
          find.text('کد منقضی شد. از پایین کد جدید بخواهید.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, 'auth-back-to-login');
        expect(find.text('خوش آمدید'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final size in [const Size(520, 360), const Size(915, 412)]) {
    testWidgets(
      'verification form scrolls in RTL at ${size.width}x${size.height}',
      (tester) async {
        await _open(
          tester,
          (request) async => request.url.path.endsWith('/login')
              ? _error('email_verification_required', 403)
              : _challenge(),
          size: size,
          language: GoldBrainLanguage.persian,
        );
        await _enterText(tester, _field('auth-email'), 'alice@example.com');
        await _enterText(tester, _field('auth-password'), 'Password1234');
        await _tap(tester, 'auth-submit');
        expect(
          Directionality.of(tester.element(_field('auth-email-code'))),
          TextDirection.rtl,
        );
        await _tap(tester, 'auth-resend-code');
        expect(find.byKey(const Key('auth-email-spam-note')), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('auth-back-to-login')));
        expect(tester.takeException(), isNull);
        await _tap(tester, 'auth-back-to-login');
        expect(find.text('خوش آمدید'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
