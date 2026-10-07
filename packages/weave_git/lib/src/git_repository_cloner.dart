import 'dart:io';

import 'package:path/path.dart' as path;

import 'git_command_runner.dart';
import 'git_exceptions.dart';
import 'git_repository_service.dart';
import 'git_repository_snapshot.dart';

/// Clones a remote Git repository into a user-selected parent directory.
final class GitRepositoryCloner {
  GitRepositoryCloner({GitCommandRunner? runner, GitRepositoryService? reader}) : _runner = runner ?? ProcessGitCommandRunner(timeout: const Duration(minutes: 10)), _reader = reader ?? GitRepositoryService();

  final GitCommandRunner _runner;
  final GitRepositoryService _reader;

  /// Clones [url] as a new child of [parentDirectory] and verifies the result.
  Future<GitRepositorySnapshot> clone(String url, {required String parentDirectory}) async {
    final String normalizedUrl = _validateUrl(url);
    final String parent = await _requireParentDirectory(parentDirectory);
    final String target = _availableTarget(parent, _repositoryName(normalizedUrl));
    final List<String> arguments = <String>['clone', '--', normalizedUrl, target];
    final GitCommandResult result = await _runner.run(arguments, workingDirectory: parent);
    if (result.exitCode != 0) {
      throw GitCommandException(arguments, result.exitCode);
    }
    return _reader.readSnapshot(target);
  }

  static String _validateUrl(String value) {
    final String url = value.trim();
    if (url.isEmpty || url.contains('\x00') || url.startsWith('-')) {
      throw const FormatException('Enter a valid Git repository URL.');
    }
    final Uri? uri = Uri.tryParse(url);
    final bool safeUri = uri != null && !uri.hasQuery && !uri.hasFragment && !uri.userInfo.contains(':');
    final bool https = uri != null && safeUri && uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;
    final bool ssh = uri != null && safeUri && uri.scheme == 'ssh' && uri.host.isNotEmpty;
    final bool scp = RegExp(r'^[^\s/@]+@[^\s/:]+:[^\s]+$').hasMatch(url);
    if (!https && !ssh && !scp) {
      throw const FormatException('Use an HTTPS or SSH Git repository URL without embedded credentials.');
    }
    return url;
  }

  static Future<String> _requireParentDirectory(String value) async {
    final String parent = path.normalize(value.trim());
    if (value.trim().isEmpty || value.contains('\x00') || !path.isAbsolute(parent) || await FileSystemEntity.type(parent) != FileSystemEntityType.directory) {
      throw const FormatException('Choose an existing local folder for the clone.');
    }
    return parent;
  }

  static String _repositoryName(String url) {
    final String location = url.startsWith('ssh://') || url.startsWith('https://') ? Uri.parse(url).path : url.substring(url.indexOf(':') + 1);
    String name = path.basename(location.endsWith('/') ? location.substring(0, location.length - 1) : location);
    if (name.endsWith('.git')) {
      name = name.substring(0, name.length - 4);
    }
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    if (name.isEmpty || name == '.' || name == '..') {
      throw const FormatException('The repository URL does not contain a usable project name.');
    }
    return name;
  }

  static String _availableTarget(String parent, String name) {
    String target = path.join(parent, name);
    int suffix = 2;
    while (FileSystemEntity.typeSync(target, followLinks: false) != FileSystemEntityType.notFound) {
      target = path.join(parent, '$name-$suffix');
      suffix++;
    }
    return target;
  }
}
