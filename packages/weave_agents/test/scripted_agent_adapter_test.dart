import 'package:test/test.dart';
import 'package:weave_agents/testing.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';

void main() {
  final AgentRunRequest request = AgentRunRequest(
    task: WorkflowTask.create(id: 'task-1', request: 'Build Weave', repositoryPath: '/repo', createdAt: DateTime.utc(2026)),
    role: AgentRole.implementer,
    instructions: 'Implement',
    workingDirectory: '/repo',
  );

  test('streams output and completes with a session ID', () async {
    final ScriptedAgentAdapter adapter = ScriptedAgentAdapter(
      id: 'scripted',
      handler: (AgentRunRequest request, ScriptedAgentSession session) {
        session.write('working\n');
        return 'Implemented ${request.role.name}';
      },
    );

    final AgentExecution execution = await adapter.start(request);
    final List<AgentEvent> events = await execution.events.toList();

    expect(adapter.requests.single, same(request));
    expect((events.first as AgentOutputEvent).text, 'working\n');
    expect(events.last, isA<AgentCompletedEvent>().having((AgentCompletedEvent event) => event.summary, 'summary', 'Implemented implementer').having((AgentCompletedEvent event) => event.sessionId, 'sessionId', 'scripted-session-1'));
    expect((await adapter.checkAvailability()).isAvailable, isTrue);
  });

  test('waits for approval decisions', () async {
    final ScriptedAgentAdapter adapter = ScriptedAgentAdapter(
      id: 'scripted',
      handler: (AgentRunRequest request, ScriptedAgentSession session) async {
        final ApprovalDecision decision = await session.requestApproval(action: 'git push', details: 'Push main');
        return decision.name;
      },
    );
    final AgentExecution execution = await adapter.start(request);

    final List<AgentEvent> events = <AgentEvent>[];
    await for (final AgentEvent event in execution.events) {
      events.add(event);
      if (event is AgentApprovalRequestedEvent) {
        await execution.resolveApproval(approvalId: event.approvalId, decision: ApprovalDecision.approve);
      }
    }

    expect((events.last as AgentCompletedEvent).summary, 'approve');
    await expectLater(execution.resolveApproval(approvalId: 'approval-1', decision: ApprovalDecision.deny), throwsStateError);
  });

  test('fails when the handler throws', () async {
    final ScriptedAgentAdapter adapter = ScriptedAgentAdapter(id: 'scripted', isAvailable: false, handler: (AgentRunRequest request, ScriptedAgentSession session) => throw StateError('boom'));

    final List<AgentEvent> events = await (await adapter.start(request)).events.toList();

    expect((events.single as AgentFailedEvent).message, contains('boom'));
    expect((await adapter.checkAvailability()).isAvailable, isFalse);
  });

  test('cancels a pending execution', () async {
    final ScriptedAgentAdapter adapter = ScriptedAgentAdapter(
      id: 'scripted',
      handler: (AgentRunRequest request, ScriptedAgentSession session) async {
        await session.requestApproval(action: 'wait', details: 'forever');
        return 'unreachable';
      },
    );
    final AgentExecution execution = await adapter.start(request);
    final Future<List<AgentEvent>> events = execution.events.toList();
    await Future<void>.delayed(Duration.zero);

    await execution.cancel();

    expect((await events).last, isA<AgentFailedEvent>());
  });
}
