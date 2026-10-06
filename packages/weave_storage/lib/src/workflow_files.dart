import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// The directory of [taskId] below [workflowsDirectory].
Directory workflowTaskDirectory(String workflowsDirectory, String taskId) => encodedDirectory(workflowsDirectory, taskId, name: 'taskId');

/// The directory for [key] below [parent].
///
/// The key is Base64 URL encoded, so any text, including a path, maps to a
/// single directory name that can never escape [parent].
Directory encodedDirectory(String parent, String key, {String name = 'key'}) {
  if (key.trim().isEmpty) {
    throw ArgumentError.value(key, name, 'must not be empty');
  }
  final String encodedKey = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
  return Directory(path.join(parent, encodedKey));
}

/// Replaces [target] with [contents] through a temporary file and rename, so
/// readers never observe a partially written file.
Future<void> writeFileAtomically(File target, String contents) async {
  await target.parent.create(recursive: true);
  final File temporary = File('${target.path}.$pid-${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(target.path);
  } on Object {
    if (await temporary.exists()) {
      await temporary.delete();
    }
    rethrow;
  }
}

/// Pretty JSON followed by a newline.
String encodePrettyJson(Object? value) => '${const JsonEncoder.withIndent('  ').convert(value)}\n';
