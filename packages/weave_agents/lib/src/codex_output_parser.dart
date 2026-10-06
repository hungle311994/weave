import 'agent_event.dart';
import 'json_lines.dart';
import 'process_agent_execution.dart';

/// Parses the JSON Lines events printed by `codex exec --json`.
final class CodexOutputParser implements AgentOutputParser {
  String? _sessionId;
  String? _lastMessage;
  String? _failure;
  bool _turnCompleted = false;
  AgentUsage _usage = AgentUsage.zero;

  @override
  Iterable<AgentEvent> parseLine(String line, DateTime timestamp) {
    final Map<String, Object?>? json = decodeJsonLine(line);
    if (json == null) {
      return line.trim().isEmpty ? const <AgentEvent>[] : <AgentEvent>[AgentOutputEvent(timestamp: timestamp, text: '$line\n')];
    }

    AgentEvent output(String text, [AgentOutputChannel channel = AgentOutputChannel.stdout]) => AgentOutputEvent(timestamp: timestamp, text: text, channel: channel);

    switch (readText(json, 'type')) {
      case 'thread.started':
        _sessionId = readText(json, 'thread_id') ?? _sessionId;
      case 'turn.completed':
        _turnCompleted = true;
        // Codex reports cached tokens as part of input_tokens.
        final Map<String, Object?>? usage = readObject(json, 'usage');
        final int input = (usage?['input_tokens'] as num?)?.toInt() ?? 0;
        final int cached = (usage?['cached_input_tokens'] as num?)?.toInt() ?? 0;
        _usage = _usage + AgentUsage(inputTokens: input - cached < 0 ? 0 : input - cached, cachedInputTokens: cached, outputTokens: (usage?['output_tokens'] as num?)?.toInt() ?? 0);
      case 'turn.failed':
        _failure = readText(readObject(json, 'error'), 'message') ?? 'Codex reported a failed turn.';
      case 'error':
        final String message = readText(json, 'message') ?? 'Codex reported an error.';
        _failure = message;
        return <AgentEvent>[output('$message\n', AgentOutputChannel.stderr)];
      case 'item.started':
        final Map<String, Object?>? item = readObject(json, 'item');
        if (readText(item, 'type') == 'command_execution') {
          return <AgentEvent>[output('\$ ${readText(item, 'command') ?? 'command'}\n')];
        }
      case 'item.completed':
        return _completedItem(readObject(json, 'item'), output);
    }
    return const <AgentEvent>[];
  }

  Iterable<AgentEvent> _completedItem(Map<String, Object?>? item, AgentEvent Function(String text, [AgentOutputChannel channel]) output) {
    switch (readText(item, 'type')) {
      case 'agent_message':
        final String? text = readText(item, 'text');
        if (text == null) {
          return const <AgentEvent>[];
        }
        _lastMessage = text;
        return <AgentEvent>[output(text.endsWith('\n') ? text : '$text\n')];
      case 'command_execution':
        final Object? exitCode = item?['exit_code'];
        return <AgentEvent>[output('  exit ${exitCode ?? '?'}\n')];
      case 'file_change':
        final Object? changes = item?['changes'];
        if (changes is! List<Object?>) {
          return const <AgentEvent>[];
        }
        return <AgentEvent>[
          for (final Map<String, Object?> change in changes.whereType<Map<String, Object?>>())
            if (readText(change, 'path') case final String path?) output('  ${readText(change, 'kind') ?? 'update'} $path\n'),
        ];
      case 'mcp_tool_call':
        return <AgentEvent>[output('  tool ${readText(item, 'tool') ?? 'call'}\n')];
      case 'web_search':
        return <AgentEvent>[output('  web search\n')];
      case 'error':
        final String? message = readText(item, 'message');
        return message == null ? const <AgentEvent>[] : <AgentEvent>[output('$message\n', AgentOutputChannel.stderr)];
    }
    return const <AgentEvent>[];
  }

  @override
  AgentEvent finish(int exitCode, DateTime timestamp) {
    final String? failure = _failure;
    if (failure != null) {
      return AgentFailedEvent(timestamp: timestamp, message: failure, exitCode: exitCode, sessionId: _sessionId, usage: _usage);
    }
    if (exitCode != 0 || !_turnCompleted) {
      return AgentFailedEvent(timestamp: timestamp, message: 'Codex exited with code $exitCode before finishing its turn.', exitCode: exitCode, sessionId: _sessionId, usage: _usage);
    }
    return AgentCompletedEvent(timestamp: timestamp, summary: _lastMessage ?? 'Codex finished without a final message.', sessionId: _sessionId, usage: _usage);
  }
}
