import 'dart:io';

import 'package:path/path.dart' as path;

/// Canonical directories used by Weave outside a source repository.
final class WeaveStoragePaths {
  WeaveStoragePaths._(String rootDirectory) : rootDirectory = path.normalize(rootDirectory), projectsDirectory = path.join(path.normalize(rootDirectory), 'projects'), workflowsDirectory = path.join(path.normalize(rootDirectory), 'workflows'), logsDirectory = path.join(path.normalize(rootDirectory), 'logs');

  factory WeaveStoragePaths.current({Map<String, String>? environment}) => WeaveStoragePaths.resolve(operatingSystem: Platform.operatingSystem, environment: environment ?? Platform.environment);

  factory WeaveStoragePaths.resolve({required String operatingSystem, required Map<String, String> environment}) {
    final String? override = environment['WEAVE_HOME']?.trim();
    if (override != null && override.isNotEmpty) {
      return WeaveStoragePaths._(_requireAbsolute(override, 'WEAVE_HOME'));
    }

    final String rootDirectory = switch (operatingSystem) {
      'macos' => path.join(_requiredEnvironmentPath(environment, 'HOME'), 'Library', 'Application Support', 'Weave'),
      'linux' => path.join(_linuxDataHome(environment), 'weave'),
      'windows' => path.join(_requiredEnvironmentPath(environment, 'LOCALAPPDATA'), 'Weave'),
      _ => throw UnsupportedError('Weave storage is not supported on $operatingSystem.'),
    };

    return WeaveStoragePaths._(rootDirectory);
  }

  final String rootDirectory;
  final String projectsDirectory;
  final String workflowsDirectory;
  final String logsDirectory;

  static String _linuxDataHome(Map<String, String> environment) {
    final String? xdgDataHome = environment['XDG_DATA_HOME']?.trim();
    if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
      return _requireAbsolute(xdgDataHome, 'XDG_DATA_HOME');
    }
    return path.join(_requiredEnvironmentPath(environment, 'HOME'), '.local', 'share');
  }

  static String _requiredEnvironmentPath(Map<String, String> environment, String name) {
    final String? value = environment[name]?.trim();
    if (value == null || value.isEmpty) {
      throw StateError('$name is required to resolve Weave storage.');
    }
    return _requireAbsolute(value, name);
  }

  static String _requireAbsolute(String value, String name) {
    if (!path.isAbsolute(value)) {
      throw ArgumentError.value(value, name, 'must be an absolute path');
    }
    return path.normalize(value);
  }
}
