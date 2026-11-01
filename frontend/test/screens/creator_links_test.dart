import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:goldbrain/screens/about_us_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'equal creators and all exact links open externally without duplicates',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings.motion_enabled': true,
        'settings.reduced_motion': true,
      });
      await SettingsStore.instance.load();
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launches = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          launches.add(Map<Object?, Object?>.from(call.arguments as Map));
          return true;
        }
        return false;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SingleChildScrollView(
                child: AboutUsScreen(
                  palette: themePalettes[GoldBrainTheme.pink]!,
                  selectedLanguage: GoldBrainLanguage.persian,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('هم‌سازنده · مشارکت ۵۰٪ · farland_game'),
        findsOneWidget,
      );
      expect(find.text('هم‌سازنده · مشارکت ۵۰٪'), findsOneWidget);
      expect(find.textContaining('Ali Dehghanzadeh'), findsNothing);
      const expected = {
        'یوتیوب · Farland Game': 'https://www.youtube.com/@Farland_game',
        'یوتیوب دوم · Farland Animation':
            'https://www.youtube.com/@Farland_animation',
        'کانال روبیکا · Farland Game': 'https://rubika.ir/farland_gam',
        'کانال دوم روبیکا · Farland Animation':
            'https://rubika.ir/Farland_animatio',
        'صفحه روبیکا · Farland Game': 'https://rubika.ir/farland_game',
        'صفحه دوم روبیکا · Farland Animations':
            'https://rubika.ir/Farland_animations',
        'اینستاگرام · Farland Game': 'https://www.instagram.com/farland_game',
        'کانال تلگرام · Farland Game': 'https://t.me/Farland_gam',
        'کانال دوم تلگرام · Farland Animation': 'https://t.me/Farland_animatio',
        'ربات موسیقی تلگرام': 'https://t.me/Farland_Music_bot',
        'توییچ · Farland Game': 'https://twitch.tv/farlandgame',
        'کیک · Farland Game': 'https://kick.com/farlandgame',
        'آپارات · Farland Game': 'https://aparat.com/Farland_Game',
        'یوتیوب · THE APEX': 'https://www.youtube.com/@THE_APEX_MC',
        'کانال تلگرام · THE APEX': 'https://t.me/+-3uY7eIZArVjZDE0',
        'گروه تلگرام · Minehunt': 'https://t.me/+DAq20XrkPyZhNjVk',
        'حمایت مالی · ریمیت': 'https://reymit.ir/farland_game',
        'ساندکلاد · بردیا': 'https://soundcloud.com/bardiya-kabir-798008614',
        'گیت‌هاب · FarlandGame': 'https://github.com/FarlandGame',
        'یوتیوب · ارمیا (Armiya Fabix)': 'https://www.youtube.com/@ArmiyaFabix',
      };
      for (final entry in expected.entries) {
        final finder = find.text(entry.key);
        expect(finder, findsOneWidget);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pump();
        expect(launches.last['url'], entry.value);
        expect(launches.last['useSafariVC'], false);
        expect(launches.last['useWebView'], false);
      }
      expect(launches, hasLength(20));
      expect(launches.map((e) => e['url']).toSet(), hasLength(20));
      expect(
        find.text(
          'اگه می‌خوای هر موسیقی رو پیدا کنی، بیا تو ربات تلگرامی ما و لینک ویدیوش رو بفرست.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
