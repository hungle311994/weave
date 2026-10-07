import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// Asks what to call another account of [agentName]; returns the name, or
/// `null` when cancelled. Signing in happens afterwards, in Terminal.
Future<String?> showAddAccountDialog(BuildContext context, {required String agentName}) => showDialog<String>(
  context: context,
  builder: (BuildContext context) => _AddAccountDialog(agentName: agentName),
);

class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog({required this.agentName});

  final String agentName;

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      showWeaveToast(context, message: 'Name the account, e.g. Work or Personal.', tone: WeaveToastTone.danger);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: WeaveColors.surface.withValues(alpha: 0),
    elevation: 0,
    child: WeaveDialog(
      title: 'Add ${widget.agentName} account',
      subtitle: 'Use another subscription of ${widget.agentName}. When one account reaches its usage limit, a workflow moves on to another signed-in account.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          WeaveTextField(key: const Key('account-name'), controller: _name, label: 'Account name', hintText: 'e.g. Work', autofocus: true, onSubmitted: (String _) => _save()),
          const SizedBox(height: WeaveSpacing.s12),
          Text(
            'Next, Terminal opens with ${widget.agentName}\'s sign-in for this account. It keeps the sign-in in its own folder inside Weave\'s data; Weave never sees your password or tokens.',
            style: WeaveTypography.caption,
          ),
        ],
      ),
      actions: <Widget>[
        WeaveButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        WeaveButton.primary(key: const Key('save-account'), label: 'Add and sign in', onPressed: _save),
      ],
    ),
  );
}
