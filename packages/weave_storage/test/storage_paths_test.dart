import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:weave_storage/weave_storage.dart';

void main() {
  group('WeaveStoragePaths', () {
    test('uses Application Support on macOS', () {
      final WeaveStoragePaths paths = WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: const <String, String>{'HOME': '/Users/developer'});

      expect(paths.rootDirectory, path.join('/Users/developer', 'Library', 'Application Support', 'Weave'));
      expect(paths.projectsDirectory, path.join(paths.rootDirectory, 'projects'));
      expect(paths.workflowsDirectory, path.join(paths.rootDirectory, 'workflows'));
      expect(paths.logsDirectory, path.join(paths.rootDirectory, 'logs'));
    });

    test('prefers an absolute WEAVE_HOME override', () {
      final WeaveStoragePaths paths = WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: const <String, String>{'HOME': '/Users/developer', 'WEAVE_HOME': '/Volumes/Secure/WeaveData'});

      expect(paths.rootDirectory, '/Volumes/Secure/WeaveData');
    });

    test('rejects a relative WEAVE_HOME override', () {
      expect(() => WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: const <String, String>{'WEAVE_HOME': '../source/.weave'}), throwsArgumentError);
    });

    test('requires HOME on macOS', () {
      expect(() => WeaveStoragePaths.resolve(operatingSystem: 'macos', environment: const <String, String>{}), throwsStateError);
    });

    test('uses XDG_DATA_HOME on Linux', () {
      final WeaveStoragePaths paths = WeaveStoragePaths.resolve(operatingSystem: 'linux', environment: const <String, String>{'XDG_DATA_HOME': '/data'});

      expect(paths.rootDirectory, path.join('/data', 'weave'));
    });

    test('rejects unsupported operating systems', () {
      expect(() => WeaveStoragePaths.resolve(operatingSystem: 'unknown', environment: const <String, String>{}), throwsUnsupportedError);
    });
  });
}
