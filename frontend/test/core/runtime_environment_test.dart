import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/runtime_environment.dart';

void main() {
  test('compile-time values configure mobile-style environments', () {
    final resolved = RuntimeEnvironment.resolve(
      allowedNames: const <String>{
        'GAPGPT_API_KEY',
        'GAPGPT_BASE_URL',
        'GAPGPT_MODEL',
        'NAVASAN_API_KEY',
      },
      compileTimeEnvironment: const <String, String>{
        'GAPGPT_API_KEY': 'compiled-ai-key',
        'GAPGPT_BASE_URL': 'https://openrouter.ai/api/v1',
        'GAPGPT_MODEL': 'openrouter/free',
        'NAVASAN_API_KEY': 'compiled-market-key',
      },
      processEnvironment: const <String, String>{},
      isWindows: false,
    );

    expect(resolved['GAPGPT_API_KEY'], 'compiled-ai-key');
    expect(resolved['GAPGPT_BASE_URL'], 'https://openrouter.ai/api/v1');
    expect(resolved['GAPGPT_MODEL'], 'openrouter/free');
    expect(resolved['NAVASAN_API_KEY'], 'compiled-market-key');
  });

  test('runtime values override compile-time build defaults', () {
    final resolved = RuntimeEnvironment.resolve(
      allowedNames: const <String>{'GAPGPT_API_KEY', 'NAVASAN_API_KEY'},
      compileTimeEnvironment: const <String, String>{
        'GAPGPT_API_KEY': 'compiled-ai-key',
        'NAVASAN_API_KEY': 'compiled-market-key',
      },
      processEnvironment: const <String, String>{
        'GAPGPT_API_KEY': 'runtime-ai-key',
        'NAVASAN_API_KEY': 'runtime-market-key',
      },
      isWindows: false,
    );

    expect(resolved['GAPGPT_API_KEY'], 'runtime-ai-key');
    expect(resolved['NAVASAN_API_KEY'], 'runtime-market-key');
  });

  test('fresh Windows User values override a stale process environment', () {
    final resolved = RuntimeEnvironment.resolve(
      allowedNames: const <String>{
        'GAPGPT_API_KEY',
        'GAPGPT_BASE_URL',
        'GAPGPT_MODEL',
      },
      processEnvironment: const <String, String>{
        'GAPGPT_API_KEY': 'old-process-key',
        'GAPGPT_BASE_URL': 'https://api.gapgpt.app/v1',
        'GAPGPT_MODEL': 'gpt-4o-mini',
      },
      isWindows: true,
      windowsUserEnvironmentLoader: (_) => const <String, String>{
        'GAPGPT_API_KEY': 'new-user-key',
        'GAPGPT_BASE_URL': 'https://openrouter.ai/api/v1',
        'GAPGPT_MODEL': 'openrouter/free',
      },
    );

    expect(resolved['GAPGPT_API_KEY'], 'new-user-key');
    expect(resolved['GAPGPT_BASE_URL'], 'https://openrouter.ai/api/v1');
    expect(resolved['GAPGPT_MODEL'], 'openrouter/free');
  });

  test('empty persisted values do not erase a usable process value', () {
    final resolved = RuntimeEnvironment.resolve(
      allowedNames: const <String>{'NAVASAN_API_KEY'},
      processEnvironment: const <String, String>{
        'NAVASAN_API_KEY': 'process-key',
      },
      isWindows: true,
      windowsUserEnvironmentLoader: (_) => const <String, String>{
        'NAVASAN_API_KEY': '   ',
      },
    );

    expect(resolved['NAVASAN_API_KEY'], 'process-key');
  });

  test('rejects variable names outside the explicit safe allowlist syntax', () {
    expect(
      () => RuntimeEnvironment.resolve(
        allowedNames: const <String>{'GAPGPT_API_KEY & whoami'},
        processEnvironment: const <String, String>{},
        isWindows: false,
      ),
      throwsArgumentError,
    );
  });

  test('parses only the requested REG_SZ or REG_EXPAND_SZ value', () {
    const output = '''
HKEY_CURRENT_USER\\Environment
    GAPGPT_API_KEY    REG_SZ    secret-value
    OTHER_VALUE       REG_SZ    ignored-value
''';

    expect(
      RuntimeEnvironment.parseWindowsRegistryValue(
        output,
        expectedName: 'GAPGPT_API_KEY',
      ),
      'secret-value',
    );
    expect(
      RuntimeEnvironment.parseWindowsRegistryValue(
        output,
        expectedName: 'MISSING_VALUE',
      ),
      isNull,
    );
  });
}
