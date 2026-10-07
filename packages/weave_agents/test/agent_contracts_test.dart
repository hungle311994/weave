import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';

void main() {
  final DateTime createdAt = DateTime.utc(2026, 10, 6, 10);
  final WorkflowTask task = WorkflowTask.create(id: 'task-1', request: 'Build Weave', repositoryPath: '/projects/weave', createdAt: createdAt);

  group('AgentAssignments', () {
    test('maps every role to a normalized adapter ID', () {
      final AgentAssignments assignments = AgentAssignments(plannerAgentId: ' codex ', implementerAgentId: ' claude-code ', reviewerAgentId: ' codex ');

      expect(assignments.agentIdFor(AgentRole.planner), 'codex');
      expect(assignments.agentIdFor(AgentRole.implementer), 'claude-code');
      expect(assignments.agentIdFor(AgentRole.reviewer), 'codex');
      expect(assignments.toMap(), hasLength(AgentRole.values.length));
    });

    test('rejects an empty adapter ID', () {
      expect(() => AgentAssignments(plannerAgentId: ' ', implementerAgentId: 'claude-code', reviewerAgentId: 'codex'), throwsArgumentError);
    });
  });

  group('AgentRunRequest', () {
    test('retains task context and normalizes execution input', () {
      final AgentRunRequest request = AgentRunRequest(task: task, role: AgentRole.planner, instructions: ' Analyze the request ', workingDirectory: ' /projects/weave ');

      expect(request.task, same(task));
      expect(request.role, AgentRole.planner);
      expect(request.instructions, 'Analyze the request');
      expect(request.workingDirectory, '/projects/weave');
    });

    test('rejects empty instructions', () {
      expect(() => AgentRunRequest(task: task, role: AgentRole.planner, instructions: ' ', workingDirectory: '/projects/weave'), throwsArgumentError);
    });
  });

  group('AgentAvailability', () {
    test('represents an available local agent', () {
      final AgentAvailability availability = AgentAvailability.available(version: '1.0.0', executablePath: '/usr/local/bin/agent');

      expect(availability.isAvailable, isTrue);
      expect(availability.version, '1.0.0');
      expect(availability.reason, isNull);
    });

    test('represents an unavailable local agent', () {
      final AgentAvailability availability = AgentAvailability.unavailable(reason: 'Executable not found');

      expect(availability.isAvailable, isFalse);
      expect(availability.isInstalled, isFalse);
      expect(availability.reason, 'Executable not found');
      expect(availability.version, isNull);
    });

    test('keeps installed separate from a failed health check', () {
      final AgentAvailability availability = AgentAvailability.unavailable(reason: 'Version check failed', executablePath: '/usr/local/bin/agent');

      expect(availability.isAvailable, isFalse);
      expect(availability.isInstalled, isTrue);
      expect(availability.executablePath, '/usr/local/bin/agent');
    });
  });

  group('AgentEvent', () {
    test('normalizes timestamps without changing streamed text', () {
      final AgentOutputEvent event = AgentOutputEvent(timestamp: createdAt.toLocal(), text: ' Planning complete ');

      expect(event.timestamp, createdAt);
      expect(event.text, ' Planning complete ');
      expect(event.channel, AgentOutputChannel.stdout);
    });

    test('represents an approval request', () {
      final AgentApprovalRequestedEvent event = AgentApprovalRequestedEvent(timestamp: createdAt, approvalId: 'approval-1', action: 'Write source files', details: 'Modify files inside the selected repository');

      expect(event.approvalId, 'approval-1');
      expect(event.action, 'Write source files');
    });

    test('represents completion and failure terminal events', () {
      final AgentCompletedEvent completed = AgentCompletedEvent(timestamp: createdAt, summary: 'Implementation complete', sessionId: 'session-1');
      final AgentFailedEvent failed = AgentFailedEvent(timestamp: createdAt, message: 'Agent process exited', exitCode: 1);

      expect(completed.sessionId, 'session-1');
      expect(failed.exitCode, 1);
    });
  });
}
