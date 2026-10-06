import 'dart:io';

import 'package:weave_security/weave_security.dart';

Future<void> main() async {
  final WorkspaceScope scope = await WorkspaceScope.resolve(Directory.current.absolute.path);
  final SecurityPolicy policy = SecurityPolicy(scope: scope, mode: SandboxMode.workspaceWrite);

  final GuardedOperation commit = classifyGitArguments(<String>['commit', '-m', 'Update']);
  print('git commit: ${policy.evaluate(OperationRequest(commit)).name}');

  final SecretRedactor redactor = SecretRedactor();
  print(redactor.redact('Authorization: Bearer abcdefghijklmnopqrstuvwxyz'));
}
