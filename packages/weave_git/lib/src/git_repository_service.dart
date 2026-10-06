import 'dart:io';

import 'package:path/path.dart' as path;

import 'git_command_runner.dart';
import 'git_diff.dart';
import 'git_exceptions.dart';
import 'git_repository_snapshot.dart';
import 'git_status_parser.dart';

/// Read-only queries against a local Git working tree.
///
/// Commands never take locks or refresh the index, and repository-provided
/// fsmonitor hooks are disabled because the repository may be untrusted.
final class GitRepositoryService {
  GitRepositoryService({GitCommandRunner? runner}) : _runner = runner ?? ProcessGitCommandRunner();

  final GitCommandRunner _runner;

  static const List<String> _readOnlyOptions = <String>['--no-optional-locks', '-c', 'core.fsmonitor=false'];

  static const List<String> _showTopLevelArguments = <String>[..._readOnlyOptions, 'rev-parse', '--show-toplevel'];

  static const List<String> _statusArguments = <String>[..._readOnlyOptions, 'status', '--porcelain=v2', '--branch', '-z', '--untracked-files=all'];

  /// External diff drivers and text conversion filters are repository
  /// configured commands, so they are always disabled.
  static const List<String> _diffArguments = <String>[..._readOnlyOptions, 'diff', '--no-ext-diff', '--no-textconv', '--no-color', '--find-renames'];

  /// Whether [directory] is inside a Git working tree.
  Future<bool> isRepository(String directory) async {
    try {
      await findRepositoryRoot(directory);
      return true;
    } on GitNotRepositoryException {
      return false;
    }
  }

  /// Absolute path of the working tree that contains [directory].
  Future<String> findRepositoryRoot(String directory) async {
    final String workingDirectory = await _requireDirectory(directory);
    final GitCommandResult result = await _runner.run(_showTopLevelArguments, workingDirectory: workingDirectory);

    if (result.exitCode != 0) {
      if (result.exitCode == 128 && result.stderr.contains('not a git repository')) {
        throw GitNotRepositoryException(workingDirectory);
      }
      throw GitCommandException(_showTopLevelArguments, result.exitCode);
    }

    final String rootPath = result.stdout.endsWith('\n') ? result.stdout.substring(0, result.stdout.length - 1) : result.stdout;
    if (rootPath.isEmpty || !path.isAbsolute(rootPath)) {
      throw const GitOutputFormatException('Git returned an invalid repository root.');
    }
    return rootPath;
  }

  /// Branch, `HEAD` commit, and working tree changes for [directory].
  Future<GitRepositorySnapshot> readSnapshot(String directory) async {
    final String rootPath = await findRepositoryRoot(directory);
    final GitCommandResult result = await _runner.run(_statusArguments, workingDirectory: rootPath);
    if (result.exitCode != 0) {
      throw GitCommandException(_statusArguments, result.exitCode);
    }

    final ({List<GitStatusEntry> entries, GitHead head}) status = parseGitStatusPorcelainV2(result.stdout);
    return GitRepositorySnapshot(rootPath: rootPath, head: status.head, entries: status.entries);
  }

  /// Uncommitted changes in [directory], capped at [maxCharacters].
  ///
  /// Untracked symlinks and special files are skipped so the patch never
  /// follows a link outside the repository or blocks on a pipe.
  Future<GitDiff> readDiff(String directory, {int maxCharacters = 256 * 1024}) async {
    if (maxCharacters <= 0) {
      throw ArgumentError.value(maxCharacters, 'maxCharacters', 'must be positive');
    }
    final GitRepositorySnapshot snapshot = await readSnapshot(directory);
    final String rootPath = snapshot.rootPath;
    int remaining = maxCharacters;
    bool isTruncated = false;

    String take(String text) {
      if (text.length <= remaining) {
        remaining -= text.length;
        return text;
      }
      isTruncated = true;
      final String kept = text.substring(0, remaining);
      remaining = 0;
      return kept;
    }

    final String staged = take(await _runDiff(<String>[..._diffArguments, '--cached'], rootPath));
    final String unstaged = take(await _runDiff(_diffArguments, rootPath));
    final StringBuffer untracked = StringBuffer();
    for (final GitUntrackedFile file in snapshot.untrackedFiles) {
      if (remaining == 0) {
        isTruncated = true;
        break;
      }
      final FileSystemEntityType type = await FileSystemEntity.type(path.join(rootPath, file.path), followLinks: false);
      if (type != FileSystemEntityType.file) {
        continue;
      }
      untracked.write(take(await _runDiff(<String>[..._diffArguments, '--no-index', '--', '/dev/null', file.path], rootPath, allowDifferences: true)));
    }

    return GitDiff(snapshot: snapshot, staged: staged, unstaged: unstaged, untracked: untracked.toString(), isTruncated: isTruncated);
  }

  /// `git diff --no-index` exits with 1 when the inputs differ.
  Future<String> _runDiff(List<String> arguments, String rootPath, {bool allowDifferences = false}) async {
    final GitCommandResult result = await _runner.run(arguments, workingDirectory: rootPath);
    if (result.exitCode == 0 || (allowDifferences && result.exitCode == 1)) {
      return result.stdout;
    }
    throw GitCommandException(arguments, result.exitCode);
  }

  static Future<String> _requireDirectory(String directory) async {
    if (directory.trim().isEmpty) {
      throw GitWorkingDirectoryException(directory, 'must not be empty');
    }
    if (directory.contains('\x00')) {
      throw GitWorkingDirectoryException(directory, 'must not contain NUL characters');
    }
    if (!path.isAbsolute(directory)) {
      throw GitWorkingDirectoryException(directory, 'must be an absolute path');
    }

    final String normalized = path.normalize(directory);
    if (await FileSystemEntity.type(normalized) != FileSystemEntityType.directory) {
      throw GitWorkingDirectoryException(directory, 'must be an existing directory');
    }
    return normalized;
  }
}
