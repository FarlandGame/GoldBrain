import 'dart:io';

import 'child_process_environment.dart';

typedef WindowsUserEnvironmentLoader =
    Map<String, String> Function(Set<String> allowedNames);

/// Resolves the small set of runtime settings that GoldBrain is explicitly
/// allowed to consume.
///
/// On Windows, values persisted for the current user in `HKCU\Environment`
/// take precedence over the environment inherited by the running process.
/// This is important for long-lived VS Code/terminal processes which do not
/// automatically see variables added after they were started.
class RuntimeEnvironment {
  const RuntimeEnvironment._();

  // Mobile apps do not inherit the developer machine's process environment.
  // Release builds can provide these values explicitly with --dart-define.
  // Keep the allowlist intentionally small: only settings consumed by the
  // market/AI clients belong here.
  static const Map<String, String> _compileTimeValues = <String, String>{
    'GAPGPT_API_KEY': String.fromEnvironment('GAPGPT_API_KEY'),
    'GAPGPT_BASE_URL': String.fromEnvironment('GAPGPT_BASE_URL'),
    'GAPGPT_MODEL': String.fromEnvironment('GAPGPT_MODEL'),
    'GAPGPT_FALLBACK_MODELS': String.fromEnvironment('GAPGPT_FALLBACK_MODELS'),
    'GAPGPT_PROXY_URL': String.fromEnvironment('GAPGPT_PROXY_URL'),
    'NAVASAN_API_KEY': String.fromEnvironment('NAVASAN_API_KEY'),
    'GOLDBRAIN_API_BASE_URL': String.fromEnvironment('GOLDBRAIN_API_BASE_URL'),
    'GOLDBRAIN_API_KEY': String.fromEnvironment('GOLDBRAIN_API_KEY'),
  };

  static Map<String, String> resolve({
    required Set<String> allowedNames,
    Map<String, String>? processEnvironment,
    Map<String, String>? compileTimeEnvironment,
    bool? isWindows,
    WindowsUserEnvironmentLoader? windowsUserEnvironmentLoader,
  }) {
    final validatedNames = Set<String>.unmodifiable(
      allowedNames.where(_isSafeVariableName),
    );
    if (validatedNames.length != allowedNames.length) {
      throw ArgumentError.value(
        allowedNames,
        'allowedNames',
        'Environment variable names must contain only A-Z, 0-9 and _ characters.',
      );
    }

    final compiled = compileTimeEnvironment ?? _compileTimeValues;
    final inherited = processEnvironment ?? Platform.environment;
    final resolved = <String, String>{
      for (final name in validatedNames)
        if (_nonEmpty(compiled[name]) case final value?) name: value,
      for (final name in validatedNames)
        if (_nonEmpty(inherited[name]) case final value?) name: value,
    };

    if (isWindows ?? Platform.isWindows) {
      final persisted =
          (windowsUserEnvironmentLoader ?? _readWindowsUserEnvironment)(
            validatedNames,
          );
      for (final name in validatedNames) {
        if (_nonEmpty(persisted[name]) case final value?) {
          // A newly persisted User value is authoritative. Do not let an old
          // value inherited by VS Code keep selecting the former provider.
          resolved[name] = value;
        }
      }
    }
    return Map<String, String>.unmodifiable(resolved);
  }

  static bool _isSafeVariableName(String name) =>
      RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(name);

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static Map<String, String> _readWindowsUserEnvironment(
    Set<String> allowedNames,
  ) {
    final result = <String, String>{};
    final childEnvironment = sanitizedWindowsChildEnvironment(
      parent: Platform.environment,
    );
    for (final name in allowedNames) {
      try {
        final query = Process.runSync(
          'reg.exe',
          <String>['query', r'HKCU\Environment', '/v', name],
          environment: childEnvironment,
          includeParentEnvironment: false,
          runInShell: false,
        );
        if (query.exitCode != 0) continue;
        final value = parseWindowsRegistryValue(
          query.stdout.toString(),
          expectedName: name,
        );
        if (value != null) result[name] = value;
      } on ProcessException {
        // Process environment remains a safe fallback.
      } on FileSystemException {
        // Process environment remains a safe fallback.
      }
    }
    return result;
  }

  /// Kept public for deterministic parser tests. This function never logs the
  /// registry output and returns only the requested value.
  static String? parseWindowsRegistryValue(
    String output, {
    required String expectedName,
  }) {
    if (!_isSafeVariableName(expectedName)) return null;
    final escaped = RegExp.escape(expectedName);
    final match = RegExp(
      '^\\s*$escaped\\s+REG_(?:SZ|EXPAND_SZ)\\s+(.+?)\\s*\$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(output);
    return _nonEmpty(match?.group(1));
  }
}
