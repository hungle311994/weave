import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Persists the user's explicit sidebar choice outside the active repository.
abstract interface class SidebarPreferenceStore {
  Future<bool?> readExpanded();

  Future<void> writeExpanded(bool expanded);
}

/// Stores app-shell preferences under Weave's application-support directory.
final class FileSidebarPreferenceStore implements SidebarPreferenceStore {
  FileSidebarPreferenceStore(String rootDirectory) : _file = File(path.join(rootDirectory, 'ui-preferences.json'));

  final File _file;

  @override
  Future<bool?> readExpanded() async {
    try {
      if (!await _file.exists()) {
        return null;
      }
      final Object? value = (jsonDecode(await _file.readAsString()) as Map<String, Object?>)['sidebarExpanded'];
      return value is bool ? value : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> writeExpanded(bool expanded) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(<String, Object?>{'sidebarExpanded': expanded}), flush: true);
  }
}
