import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/local_persistence_policy.dart';
import 'package:goldbrain/core/profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => LocalPersistencePolicy.instance.setSuspended(false));

  test('removes legacy demonstrative contact details on load', () async {
    SharedPreferences.setMockInitialValues({
      'profile_name': 'GoldBrain User',
      'profile_email': 'user@goldbrain.app',
      'profile_phone': '+98 912 000 0000',
    });

    await ProfileStore.instance.load();

    expect(ProfileStore.instance.email, isEmpty);
    expect(ProfileStore.instance.phone, isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('profile_email'), isFalse);
    expect(preferences.containsKey('profile_phone'), isFalse);
  });

  test('suspended persistence does not rewrite legacy placeholders', () async {
    SharedPreferences.setMockInitialValues({
      'profile_email': 'user@goldbrain.app',
      'profile_phone': '+98 912 000 0000',
    });
    LocalPersistencePolicy.instance.setSuspended(true);

    await ProfileStore.instance.load();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('profile_email'), 'user@goldbrain.app');
    expect(preferences.getString('profile_phone'), '+98 912 000 0000');
  });
}
