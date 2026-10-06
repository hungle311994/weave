import 'dart:io';

import 'package:test/test.dart';
import 'package:weave_security/weave_security.dart';
import 'package:weave_workflow/weave_workflow.dart';

void main() {
  group('splitCommandLine', () {
    test('splits words and honors quotes without expansion', () {
      expect(splitCommandLine('fvm dart test'), <String>['fvm', 'dart', 'test']);
      expect(splitCommandLine('  echo   "two  words"  \'\$HOME *\'  '), <String>['echo', 'two  words', r'$HOME *']);
      expect(splitCommandLine(r'say "a \"quoted\" word" back\ slash'), <String>['say', 'a "quoted" word', 'back slash']);
      expect(splitCommandLine('run "" end'), <String>['run', '', 'end']);
      expect(splitCommandLine('   '), isEmpty);
    });

    test('keeps quoted shell operators as plain arguments', () {
      expect(splitCommandLine('grep "a|b" ";"'), <String>['grep', 'a|b', ';']);
    });

    test('rejects shell operators and malformed quoting', () {
      for (final String commandLine in <String>['fvm dart analyze && fvm dart test', 'cat file | grep x', 'echo hi > out.txt', 'run ;', 'echo "unterminated', r'trailing\']) {
        expect(() => splitCommandLine(commandLine), throwsFormatException, reason: commandLine);
      }
    });
  });

  group('VerificationCommand', () {
    test('parses a command line and derives a label', () {
      final VerificationCommand command = VerificationCommand.parse('fvm dart analyze --fatal-infos');

      expect(command.executable, 'fvm');
      expect(command.arguments, <String>['dart', 'analyze', '--fatal-infos']);
      expect(command.label, 'fvm dart analyze --fatal-infos');
      expect(command.timeout, const Duration(minutes: 10));
    });

    test('round-trips through JSON', () {
      final VerificationCommand command = VerificationCommand(executable: 'fvm', arguments: <String>['dart', 'test'], label: 'Tests', timeout: const Duration(seconds: 90));

      final VerificationCommand restored = VerificationCommand.fromJson(command.toJson());

      expect(restored.toJson(), command.toJson());
    });

    test('rejects invalid commands', () {
      expect(() => VerificationCommand.parse(' '), throwsFormatException);
      expect(() => VerificationCommand(executable: ' '), throwsArgumentError);
      expect(() => VerificationCommand(executable: 'true', timeout: Duration.zero), throwsArgumentError);
      expect(() => VerificationCommand.fromJson(<String, Object?>{'executable': 'true', 'arguments': 'oops'}), throwsFormatException);
      expect(() => VerificationCommand.fromJson(<String, Object?>{'executable': ''}), throwsFormatException);
    });
  });

  group('ProcessVerificationRunner', () {
    late Directory temporaryDirectory;
    late ProcessVerificationRunner runner;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp('weave-verification-test-');
      runner = ProcessVerificationRunner(
        environment: <String, String>{'PATH': '/usr/bin:/bin', 'HOME': temporaryDirectory.path, 'GIT_DIR': '/elsewhere'},
        redactor: SecretRedactor(knownSecrets: <String>['secret-value-123']),
        maxOutputCharacters: 100,
        cancelGracePeriod: const Duration(milliseconds: 200),
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    Future<VerificationResult> run(String commandLine, {Duration timeout = const Duration(minutes: 1)}) => runner.run(VerificationCommand.parse(commandLine, timeout: timeout), workingDirectory: temporaryDirectory.path);

    test('passes when the command exits with zero', () async {
      final VerificationResult result = await run('true');

      expect(result.passed, isTrue);
      expect(result.exitCode, 0);
    });

    test('fails with the exit code and captured output', () async {
      final VerificationResult result = await run('ls missing-file');

      expect(result.passed, isFalse);
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('missing-file'));
    });

    test('runs in the working directory without inherited Git variables', () async {
      final VerificationResult result = await run('env');

      expect(result.output, isNot(contains('GIT_DIR')));
      expect((await run('pwd')).output.trim(), await temporaryDirectory.resolveSymbolicLinks());
    });

    test('never interprets the command through a shell', () async {
      final VerificationResult result = await run('echo "\$(touch injected)" *');

      expect(result.output.trim(), r'$(touch injected) *');
      expect(File('${temporaryDirectory.path}/injected').existsSync(), isFalse);
    });

    test('redacts secrets and keeps only the tail of long output', () async {
      final VerificationResult secret = await run('echo token secret-value-123');
      final VerificationResult long = await run('seq 1 500');

      expect(secret.output, 'token [REDACTED]\n');
      expect(long.output, startsWith('[earlier output truncated]\n'));
      expect(long.output, endsWith('500\n'));
      expect(long.output.length, lessThan(160));
    });

    test('reports a missing executable without throwing', () async {
      final VerificationResult result = await run('weave-missing-command --check');

      expect(result.passed, isFalse);
      expect(result.exitCode, isNull);
      expect(result.startError, contains('weave-missing-command'));
    });

    test('stops a command that exceeds its timeout', () async {
      final VerificationResult result = await run('sleep 30', timeout: const Duration(milliseconds: 100));

      expect(result.timedOut, isTrue);
      expect(result.passed, isFalse);
      expect(result.duration, lessThan(const Duration(seconds: 5)));
    });
  });

  test('formats a verification report', () {
    final VerificationCommand analyze = VerificationCommand.parse('fvm dart analyze');
    final VerificationCommand tests = VerificationCommand.parse('fvm dart test', timeout: const Duration(seconds: 5));

    final String report = formatVerificationReport(<VerificationResult>[
      VerificationResult(command: analyze, exitCode: 0, output: 'ignored', duration: const Duration(milliseconds: 1200)),
      VerificationResult(command: tests, exitCode: 1, output: 'Some tests failed.\n', duration: const Duration(seconds: 2)),
      VerificationResult(command: tests, exitCode: -15, output: '', duration: const Duration(seconds: 5), timedOut: true),
    ]);

    expect(report, contains('- PASS `fvm dart analyze` — exit 0 (1.2s)'));
    expect(report, contains('- FAIL `fvm dart test` — exit 1 (2.0s)\n\n```text\nSome tests failed.\n```'));
    expect(report, contains('timed out after 5s'));
    expect(report, isNot(contains('ignored')));
    expect(formatVerificationReport(const <VerificationResult>[]), 'No verification commands are configured.\n');
  });
}
