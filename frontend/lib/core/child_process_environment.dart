/// Builds a deliberately small environment for trusted Windows helper
/// processes without forwarding application secrets or proxy credentials.
Map<String, String> sanitizedWindowsChildEnvironment({
  Map<String, String>? parent,
  Map<String, String> additions = const <String, String>{},
}) {
  final source = parent ?? const <String, String>{};
  const allowed = <String>{
    'systemroot',
    'windir',
    'systemdrive',
    'comspec',
    'path',
    'pathext',
    'temp',
    'tmp',
    'processor_architecture',
    'programfiles',
    'programfiles(x86)',
    'programw6432',
  };
  final result = <String, String>{};
  for (final entry in source.entries) {
    if (allowed.contains(entry.key.toLowerCase())) {
      result[entry.key] = entry.value;
    }
  }
  result.addAll(additions);
  return result;
}
