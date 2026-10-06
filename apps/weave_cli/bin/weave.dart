import 'dart:io';

import 'package:weave_cli/weave_cli.dart';
import 'package:weave_workflow/weave_workflow.dart';

Future<void> main(List<String> arguments) async {
  final WeaveServices services;
  try {
    services = await WeaveServices.open();
  } on Object catch (error) {
    stderr.writeln('Unable to load Weave settings: $error');
    exitCode = ExitCodes.failure;
    return;
  }
  exitCode = await runWeaveCli(arguments, services: services, console: CliConsole.standard());
}
