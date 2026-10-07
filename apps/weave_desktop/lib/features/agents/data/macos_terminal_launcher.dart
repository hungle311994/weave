import 'dart:io';

import 'package:path/path.dart' as path;

import '../domain/terminal_launcher.dart';

/// Writes the command to a `.command` file in Weave's own folder and opens
/// it with Terminal, which runs it in the user's login shell. Weave starts
/// only `chmod` and `open`, each with an argument list.
final class MacosTerminalLauncher implements TerminalLauncher {
  const MacosTerminalLauncher(this._scriptsDirectory);

  final String _scriptsDirectory;

  @override
  Future<void> run(String command, {required String name}) async {
    final File script = File(path.join(_scriptsDirectory, '${name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}.command'));
    await script.parent.create(recursive: true);
    await script.writeAsString('#!/bin/sh\n# Opened by Weave so you can sign in; safe to delete.\n$command\n', flush: true);
    final ProcessResult chmod = await Process.run('/bin/chmod', <String>['700', script.path]);
    final ProcessResult open = chmod.exitCode == 0 ? await Process.run('/usr/bin/open', <String>['-a', 'Terminal', script.path]) : chmod;
    if (open.exitCode != 0) {
      throw StateError('Terminal could not be opened. Run this in Terminal instead: $command');
    }
  }
}
