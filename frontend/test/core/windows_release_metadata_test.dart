import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Windows executable metadata contains production GoldBrain identity',
    () {
      final resource = File('windows/runner/Runner.rc').readAsStringSync();
      final runner = File('windows/runner/main.cpp').readAsStringSync();

      expect(resource, contains('VALUE "CompanyName", "GoldBrain"'));
      expect(resource, contains('VALUE "ProductName", "GoldBrain"'));
      expect(resource, isNot(contains('com.example')));
      expect(runner, contains('window.Create(L"GoldBrain"'));
    },
  );
}
