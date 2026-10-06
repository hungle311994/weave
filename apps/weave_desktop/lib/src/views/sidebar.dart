import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:weave_core/weave_core.dart';

import '../weave_controller.dart';
import 'status_chip.dart';

/// Navigation between the new-workflow form, agents, and past workflows.
class Sidebar extends StatelessWidget {
  const Sidebar({required this.controller, super.key});

  final WeaveController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WeaveSelection selection = controller.selection;
    // A Material, not a ColoredBox, so list tiles can paint selection and ink.
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text('Weave', style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              onPressed: () => controller.select(const NewWorkflowSelection()),
              icon: const Icon(Icons.add),
              label: const Text('New workflow'),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            dense: true,
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Agents'),
            selected: selection is AgentsSelection,
            onTap: () => controller.select(const AgentsSelection()),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.extension_outlined),
            title: const Text('MCP servers'),
            selected: selection is McpSelection,
            onTap: () => controller.select(const McpSelection()),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Workflows', style: theme.textTheme.labelMedium),
          ),
          Expanded(
            child: controller.tasks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No workflows yet.', style: theme.textTheme.bodySmall),
                  )
                : ListView.builder(
                    itemCount: controller.tasks.length,
                    itemBuilder: (BuildContext context, int index) {
                      final WorkflowTask task = controller.tasks[index];
                      return _WorkflowTile(
                        task: task,
                        isRunning: controller.isRunning(task.id),
                        isInterrupted: controller.isInterrupted(task.id),
                        selected: selection is WorkflowSelection && selection.taskId == task.id,
                        onTap: () => controller.select(WorkflowSelection(task.id)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowTile extends StatelessWidget {
  const _WorkflowTile({
    required this.task,
    required this.isRunning,
    required this.isInterrupted,
    required this.selected,
    required this.onTap,
  });

  final WorkflowTask task;
  final bool isRunning;
  final bool isInterrupted;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    selected: selected,
    onTap: onTap,
    title: Text(task.request.split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          StatusChip(task.status),
          const SizedBox(width: 8),
          Expanded(child: Text(path.basename(task.repositoryPath), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    ),
    trailing: isRunning
        ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
        : isInterrupted
        ? const Tooltip(message: 'Interrupted — open it to resume', child: Icon(Icons.pause_circle_outline, size: 18))
        : null,
  );
}
