import 'dart:convert';

import 'package:test/test.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_security/weave_security.dart';

void main() {
  test('catalog agents have unique IDs that never replace a built-in preset', () {
    final List<String> ids = <String>[for (final AgentCatalogEntry entry in agentCatalog) entry.definition.id];

    expect(ids.toSet(), hasLength(ids.length));
    expect(ids.toSet().intersection(<String>{for (final AgentDefinition preset in AgentRegistry.builtInDefinitions) preset.id}), isEmpty);
  });

  test('every catalog agent takes the prompt on stdin and confines read-only roles', () {
    for (final AgentCatalogEntry entry in agentCatalog) {
      final AgentDefinition agent = entry.definition;
      expect(agent.takesPromptArgument, isFalse, reason: '${agent.id}: the prompt must not appear in the process list');
      expect(agent.sandboxArguments[SandboxMode.readOnly], isNotEmpty, reason: '${agent.id} states how it stays read-only');
      expect(agent.installOptions, isNotEmpty, reason: '${agent.id} says how to install it');
      expect(agent.signInCommand, isNotEmpty);
      expect(BrandMarkNames.known, contains(agent.brand), reason: '${agent.id} shows a logo the app has');
    }
  });

  test('catalog agents survive agents.json unchanged', () {
    for (final AgentCatalogEntry entry in agentCatalog) {
      final AgentDefinition restored = AgentDefinition.fromJson(jsonDecode(jsonEncode(entry.definition.toJson())) as Map<String, Object?>);
      expect(jsonEncode(restored.toJson()), jsonEncode(entry.definition.toJson()));
    }
  });

  test('Gemini CLI plans read-only and edits only with auto_edit', () {
    final AgentDefinition gemini = agentCatalog.firstWhere((AgentCatalogEntry entry) => entry.definition.id == 'gemini').definition;
    expect(gemini.sandboxArguments[SandboxMode.readOnly], <String>['--approval-mode', 'plan']);
    expect(gemini.sandboxArguments[SandboxMode.workspaceWrite], <String>['--approval-mode', 'auto_edit']);
  });
}

/// Brand marks the desktop app ships (`assets/icons/brand`).
abstract final class BrandMarkNames {
  static const Set<String> known = <String>{'openai', 'anthropic', 'gemini', 'figma', 'github', 'linear', 'sentry'};
}
