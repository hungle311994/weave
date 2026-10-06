import 'agent_event.dart';
import 'json_lines.dart';
import 'process_agent_execution.dart';

/// Parses the stream-json messages printed by `claude --print`.
final class ClaudeCodeOutputParser implements AgentOutputParser {
  String? _sessionId;
  String? _result;
  bool? _isError;
  AgentUsage? _usage;

  @override
  Iterable<AgentEvent> parseLine(String line, DateTime timestamp) {
    final Map<String, Object?>? json = decodeJsonLine(line);
    if (json == null) {
      return line.trim().isEmpty ? const <AgentEvent>[] : <AgentEvent>[AgentOutputEvent(timestamp: timestamp, text: '$line\n')];
    }

    _sessionId = readText(json, 'session_id') ?? _sessionId;
    AgentEvent output(String text, [AgentOutputChannel channel = AgentOutputChannel.stdout]) => AgentOutputEvent(timestamp: timestamp, text: text, channel: channel);

    switch (readText(json, 'type')) {
      case 'assistant':
        final Object? content = readObject(json, 'message')?['content'];
        if (content is! List<Object?>) {
          return const <AgentEvent>[];
        }
        return <AgentEvent>[
          for (final Map<String, Object?> block in content.whereType<Map<String, Object?>>())
            ?switch (readText(block, 'type')) {
              'text' => switch (readText(block, 'text')) {
                final String text? => output(text.endsWith('\n') ? text : '$text\n'),
                null => null,
              },
              'tool_use' => output(_describeToolUse(block)),
              _ => null,
            },
        ];
      case 'result':
        _result = readText(json, 'result');
        _isError = json['is_error'] == true || readText(json, 'subtype') != 'success';
        final Map<String, Object?>? usage = readObject(json, 'usage');
        int tokens(String key) => (usage?[key] as num?)?.toInt() ?? 0;
        _usage = AgentUsage(
          inputTokens: tokens('input_tokens') + tokens('cache_creation_input_tokens'),
          cachedInputTokens: tokens('cache_read_input_tokens'),
          outputTokens: tokens('output_tokens'),
          costUsd: (json['total_cost_usd'] as num?)?.toDouble(),
        );
        final Object? denials = json['permission_denials'];
        if (denials is List<Object?> && denials.isNotEmpty) {
          return <AgentEvent>[output('${denials.length} tool call(s) were denied by the sandbox.\n', AgentOutputChannel.stderr)];
        }
    }
    return const <AgentEvent>[];
  }

  static String _describeToolUse(Map<String, Object?> block) {
    final String name = readText(block, 'name') ?? 'tool';
    final Map<String, Object?>? input = readObject(block, 'input');
    final String? target = readText(input, 'file_path') ?? readText(input, 'path') ?? readText(input, 'pattern');
    return target == null ? '  tool $name\n' : '  tool $name $target\n';
  }

  @override
  AgentEvent finish(int exitCode, DateTime timestamp) {
    final String? result = _result;
    if (_isError == false && exitCode == 0) {
      return AgentCompletedEvent(timestamp: timestamp, summary: result ?? 'Claude Code finished without a final message.', sessionId: _sessionId, usage: _usage);
    }
    return AgentFailedEvent(
      timestamp: timestamp,
      message: _isError == null ? 'Claude Code exited with code $exitCode before reporting a result.' : result ?? 'Claude Code reported an error.',
      exitCode: exitCode,
      sessionId: _sessionId,
      usage: _usage,
    );
  }
}
