import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../weave_controller.dart';

/// Every assignable agent and whether it is installed.
class AgentsView extends StatelessWidget {
  const AgentsView({required this.controller, super.key});

  final WeaveController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text('Agents', style: theme.textTheme.headlineSmall)),
            OutlinedButton.icon(onPressed: controller.refreshAgents, icon: const Icon(Icons.refresh), label: const Text('Check again')),
          ],
        ),
        const SizedBox(height: 8),
        Text('Any agent can plan, implement, or review. Add other command-line agents, or override a built-in one, in:', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        SelectableText(agentsFilePath(controller.services.paths), style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo')),
        const SizedBox(height: 16),
        for (final AgentAdapter adapter in controller.agents) _AgentCard(adapter: adapter, availability: controller.availabilityOf(adapter.id)),
      ],
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.adapter, required this.availability});

  final AgentAdapter adapter;
  final AgentAvailability? availability;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final AgentAvailability? availability = this.availability;
    final String detail = switch (availability) {
      null => 'Checking...',
      AgentAvailability(isAvailable: true) => '${availability.version} — ${availability.executablePath}',
      _ => availability.reason ?? 'Not available',
    };
    final String kind = switch (adapter) {
      CommandAgentAdapter(:final AgentDefinition definition) => '${definition.executable} · ${definition.outputFormat.jsonName}',
      _ => 'in-process',
    };
    final String? signIn = availability?.signInCommand;
    return Card(
      child: ListTile(
        leading: Icon(
          availability?.isAvailable ?? false
              ? Icons.check_circle
              : signIn != null
              ? Icons.login
              : Icons.error_outline,
          color: availability?.isAvailable ?? false ? colors.primary : colors.error,
        ),
        title: Text('${adapter.displayName}  (${adapter.id})'),
        subtitle: Text('$kind\n$detail'),
        isThreeLine: true,
        // Weave never asks for passwords: the agent signs in through its own
        // command and keeps the credentials in its own store.
        trailing: signIn == null
            ? null
            : FilledButton.tonalIcon(
                key: Key('copy-sign-in-${adapter.id}'),
                onPressed: () async {
                  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: signIn));
                  messenger.showSnackBar(SnackBar(content: Text('Copied `$signIn`. Run it in Terminal, then choose Check again.')));
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy sign-in command'),
              ),
      ),
    );
  }
}
