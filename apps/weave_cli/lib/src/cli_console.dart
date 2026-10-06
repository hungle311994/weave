import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Terminal input and output, replaceable in tests.
final class CliConsole {
  CliConsole({required this.out, required this.error, required this._input, required this._interrupts});

  /// The process's stdin, stdout, stderr, and Ctrl+C.
  factory CliConsole.standard() => CliConsole(
    out: stdout,
    error: stderr,
    input: stdin.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()),
    interrupts: () => ProcessSignal.sigint.watch().map((ProcessSignal _) {}),
  );

  final StringSink out;
  final StringSink error;
  final Stream<String> _input;
  final Stream<void> Function() _interrupts;
  StreamIterator<String>? _lines;

  /// Ctrl+C presses; listening replaces the default exit behavior.
  Stream<void> get interrupts => _interrupts();

  /// The next input line, or `null` at end of input.
  Future<String?> readLine() async {
    final StreamIterator<String> lines = _lines ??= StreamIterator<String>(_input);
    return await lines.moveNext() ? lines.current : null;
  }

  /// Releases stdin so the process can exit.
  Future<void> close() async => _lines?.cancel();
}
