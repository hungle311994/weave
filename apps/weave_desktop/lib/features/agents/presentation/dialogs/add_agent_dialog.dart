import 'package:flutter/material.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../../../../core/design_system/design_system.dart';

/// Asks for a command-line agent and returns its definition for
/// `agents.json`; nothing is run or saved here.
Future<AgentDefinition?> showAddAgentDialog(BuildContext context, {required Set<String> existingIds}) => showDialog<AgentDefinition>(
  context: context,
  builder: (BuildContext context) => _AddAgentDialog(existingIds: existingIds),
);

class _AddAgentDialog extends StatefulWidget {
  const _AddAgentDialog({required this.existingIds});

  /// IDs already in use; saving one replaces that agent.
  final Set<String> existingIds;

  @override
  State<_AddAgentDialog> createState() => _AddAgentDialogState();
}

class _AddAgentDialogState extends State<_AddAgentDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _id = TextEditingController();
  final TextEditingController _vendor = TextEditingController();
  final TextEditingController _executable = TextEditingController();
  final TextEditingController _arguments = TextEditingController();
  final TextEditingController _readOnly = TextEditingController();
  final TextEditingController _write = TextEditingController();
  final TextEditingController _signInCheck = TextEditingController();
  final TextEditingController _signIn = TextEditingController();
  AgentOutputFormat _format = AgentOutputFormat.text;

  /// The ID follows the name until the user edits it.
  bool _idEdited = false;
  String? _error;

  List<TextEditingController> get _controllers => <TextEditingController>[_name, _id, _vendor, _executable, _arguments, _readOnly, _write, _signInCheck, _signIn];

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _slug(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

  void _save() {
    try {
      final String? vendor = _vendor.text.trim().isEmpty ? null : _vendor.text.trim();
      // Built as agents.json data, so it is validated exactly like the file.
      final AgentDefinition definition = AgentDefinition.fromJson(<String, Object?>{
        'id': _id.text.trim(),
        'displayName': _name.text.trim(),
        'executable': _executable.text.trim(),
        'vendor': ?vendor,
        'arguments': splitCommandLine(_arguments.text),
        'sandboxArguments': <String, Object?>{'readOnly': splitCommandLine(_readOnly.text), 'workspaceWrite': splitCommandLine(_write.text)},
        'outputFormat': _format.jsonName,
        'authStatusArguments': splitCommandLine(_signInCheck.text),
        'signInCommand': splitCommandLine(_signIn.text),
      });
      Navigator.of(context).pop(definition);
    } on ArgumentError catch (error) {
      setState(() => _error = '${error.name ?? 'Value'} ${error.message}');
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String id = _id.text.trim();
    return Dialog(
      backgroundColor: WeaveColors.surface.withValues(alpha: 0),
      elevation: 0,
      child: WeaveDialog(
        title: 'Add agent',
        subtitle: 'Any command-line coding agent. Weave saves it to agents.json and never stores its credentials.',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WeaveTextField(
              key: const Key('agent-name'),
              controller: _name,
              label: 'Name',
              hintText: 'e.g. Gemini CLI',
              autofocus: true,
              onChanged: (String name) => setState(() {
                _error = null;
                if (!_idEdited) {
                  _id.text = _slug(name);
                }
              }),
            ),
            const SizedBox(height: WeaveSpacing.s16),
            WeaveTextField(
              key: const Key('agent-id'),
              controller: _id,
              label: 'ID',
              hintText: 'e.g. gemini',
              helperText: widget.existingIds.contains(id) ? 'An agent with this ID exists; saving replaces it.' : 'Lowercase letters, digits, dots, dashes; used in settings and agents.json.',
              onChanged: (String _) => setState(() {
                _idEdited = true;
                _error = null;
              }),
            ),
            const SizedBox(height: WeaveSpacing.s16),
            WeaveTextField(key: const Key('agent-vendor'), controller: _vendor, label: 'Made by (optional)', hintText: 'e.g. Google'),
            const SizedBox(height: WeaveSpacing.s16),
            WeaveTextField(key: const Key('agent-executable'), controller: _executable, label: 'Command', hintText: 'e.g. gemini', helperText: 'The program to run, found on your PATH or as an absolute path.'),
            const SizedBox(height: WeaveSpacing.s16),
            WeaveTextField(
              key: const Key('agent-arguments'),
              controller: _arguments,
              label: 'Arguments (optional)',
              hintText: 'e.g. --non-interactive',
              helperText: 'Weave sends the prompt on stdin, unless an argument contains {prompt}. {workingDirectory} and {model} are filled in.',
            ),
            const SizedBox(height: WeaveSpacing.s16),
            WeaveTextField(key: const Key('agent-readonly-arguments'), controller: _readOnly, label: 'Read-only arguments', hintText: 'e.g. --sandbox read-only', helperText: 'Added for the planner and reviewer, which must not edit files.'),
            const SizedBox(height: WeaveSpacing.s16),
            WeaveTextField(key: const Key('agent-write-arguments'), controller: _write, label: 'Edit arguments (optional)', hintText: 'e.g. --sandbox workspace-write', helperText: 'Added for the implementer, which may edit the working tree.'),
            const SizedBox(height: WeaveSpacing.s16),
            WeaveSelect<AgentOutputFormat>(
              key: const Key('agent-output-format'),
              label: 'Output',
              semanticLabel: 'Output format',
              value: _format,
              options: <WeavePopoverItem<AgentOutputFormat>>[
                for (final AgentOutputFormat format in AgentOutputFormat.values)
                  WeavePopoverItem<AgentOutputFormat>(
                    value: format,
                    title: switch (format) {
                      AgentOutputFormat.text => 'Plain text',
                      AgentOutputFormat.codexJsonl => 'Codex JSON events',
                      AgentOutputFormat.claudeStreamJson => 'Claude Code stream JSON',
                    },
                    subtitle: format.jsonName,
                    icon: WeaveIcons.terminal,
                    selected: format == _format,
                  ),
              ],
              onChanged: (AgentOutputFormat format) => setState(() => _format = format),
            ),
            const SizedBox(height: WeaveSpacing.s16),
            WeaveTextField(key: const Key('agent-sign-in-check'), controller: _signInCheck, label: 'Sign-in check (optional)', hintText: 'e.g. auth status', helperText: 'Arguments that exit with 0 when the agent is signed in.'),
            const SizedBox(height: WeaveSpacing.s16),
            WeaveTextField(key: const Key('agent-sign-in'), controller: _signIn, label: 'Sign-in command (optional)', hintText: 'e.g. gemini auth login', helperText: 'Shown to you to run in Terminal; Weave never runs it.'),
            if (_error case final String error) ...<Widget>[
              const SizedBox(height: WeaveSpacing.s12),
              Text(
                error,
                key: const Key('agent-error'),
                style: WeaveTypography.bodySmall.copyWith(color: WeaveColors.red),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          WeaveButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
          WeaveButton.primary(key: const Key('save-agent'), label: 'Add agent', onPressed: _save),
        ],
      ),
    );
  }
}
