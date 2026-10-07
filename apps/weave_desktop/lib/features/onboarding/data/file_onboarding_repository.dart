import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../domain/onboarding_repository.dart';

/// Stores non-sensitive onboarding state under Weave's application support
/// directory, never in an active repository.
final class FileOnboardingRepository implements OnboardingRepository {
  FileOnboardingRepository(String rootDirectory) : _file = File(path.join(rootDirectory, 'onboarding.json'));

  final File _file;

  @override
  Future<bool> isCompleted() async {
    try {
      if (!await _file.exists()) {
        return false;
      }
      final Object? decoded = jsonDecode(await _file.readAsString());
      return decoded is Map<String, Object?> && decoded['completed'] == true;
    } on FileSystemException {
      return false;
    } on FormatException {
      return false;
    }
  }

  @override
  Future<void> markCompleted() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(<String, Object?>{'completed': true}), flush: true);
  }
}
