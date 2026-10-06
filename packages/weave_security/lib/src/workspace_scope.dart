import 'dart:io';

import 'package:path/path.dart' as path;

/// The directory tree an execution is allowed to touch without approval.
final class WorkspaceScope {
  WorkspaceScope._(this.rootPath);

  /// Resolves [rootPath] to its canonical location, following symlinks.
  static Future<WorkspaceScope> resolve(String rootPath) async {
    if (rootPath.trim().isEmpty || !path.isAbsolute(rootPath)) {
      throw ArgumentError.value(rootPath, 'rootPath', 'must be an absolute path');
    }
    final Directory directory = Directory(path.normalize(rootPath));
    if (!await directory.exists()) {
      throw ArgumentError.value(rootPath, 'rootPath', 'must be an existing directory');
    }
    return WorkspaceScope._(await directory.resolveSymbolicLinks());
  }

  /// Canonical absolute root of the workspace.
  final String rootPath;

  /// Whether [candidate] is the root or below it, judged lexically.
  ///
  /// Relative candidates are interpreted from [rootPath]; `..` segments are
  /// normalized before the check, so they cannot escape the root.
  bool containsPath(String candidate) {
    if (candidate.trim().isEmpty) {
      return false;
    }
    final String absolute = path.normalize(path.isAbsolute(candidate) ? candidate : path.join(rootPath, candidate));
    return absolute == rootPath || path.isWithin(rootPath, absolute);
  }

  /// Like [containsPath], but follows symlinks in the existing part of
  /// [candidate] so a link inside the workspace cannot point outside it.
  Future<bool> containsResolvedPath(String candidate) async {
    if (!containsPath(candidate)) {
      return false;
    }
    final String absolute = path.normalize(path.isAbsolute(candidate) ? candidate : path.join(rootPath, candidate));

    String existing = absolute;
    final List<String> missingSegments = <String>[];
    while (await FileSystemEntity.type(existing, followLinks: false) == FileSystemEntityType.notFound) {
      final String parent = path.dirname(existing);
      if (parent == existing) {
        return false;
      }
      missingSegments.insert(0, path.basename(existing));
      existing = parent;
    }

    final String resolved = path.joinAll(<String>[await File(existing).resolveSymbolicLinks(), ...missingSegments]);
    return containsPath(resolved);
  }
}
