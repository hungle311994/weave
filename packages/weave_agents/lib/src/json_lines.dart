import 'dart:convert';

/// Decodes one JSON Lines record, or returns `null` for non-object lines.
Map<String, Object?>? decodeJsonLine(String line) {
  final String trimmed = line.trim();
  if (!trimmed.startsWith('{')) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(trimmed);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Reads a non-blank string field.
String? readText(Map<String, Object?>? json, String key) {
  final Object? value = json?[key];
  return value is String && value.trim().isNotEmpty ? value : null;
}

/// Reads a nested object field.
Map<String, Object?>? readObject(Map<String, Object?>? json, String key) {
  final Object? value = json?[key];
  return value is Map<String, Object?> ? value : null;
}
