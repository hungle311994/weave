import 'dart:io';

import 'package:path/path.dart' as path;

/// Finds agent executables even when launched with a minimal GUI `PATH`.
final class AgentExecutableLocator {
  AgentExecutableLocator({Map<String, String>? environment}) : _environment = environment ?? Platform.environment;

  final Map<String, String> _environment;

  /// Directories searched in order: `PATH`, then common install locations.
  List<String> get searchDirectories {
    final String? home = _environment['HOME'];
    final List<String> directories = <String>[
      ...?_environment['PATH']?.split(':'),
      if (home != null) ...<String>[
        path.join(home, '.local', 'bin'),
        path.join(home, '.npm-global', 'bin'),
        path.join(home, '.bun', 'bin'),
        path.join(home, '.volta', 'bin'),
        path.join(home, '.cargo', 'bin'),
        path.join(home, '.pub-cache', 'bin'),
      ],
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
    ];
    return <String>[
      for (final String directory in directories.toSet())
        if (directory.isNotEmpty && path.isAbsolute(directory)) directory,
    ];
  }

  /// `PATH` for agent processes, so they can find Git and their runtimes.
  String get searchPath => searchDirectories.join(':');

  /// Absolute path of [name], or `null` when it is not installed.
  Future<String?> locate(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (path.isAbsolute(name)) {
      return await _isExecutableFile(name) ? name : null;
    }
    if (name.contains('/')) {
      throw ArgumentError.value(name, 'name', 'must be a bare name');
    }

    for (final String directory in searchDirectories) {
      final String candidate = path.join(directory, name);
      if (await _isExecutableFile(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static Future<bool> _isExecutableFile(String candidate) async {
    final FileStat stat = await FileStat.stat(candidate);
    return stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0;
  }
}
