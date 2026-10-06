import 'package:flutter/material.dart';
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../weave_controller.dart';

/// Built-in and custom MCP servers, and a form to add one.
class McpView extends StatefulWidget {
  const McpView({required this.controller, super.key});

  final WeaveController controller;

  @override
  State<McpView> createState() => _McpViewState();
}

class _McpViewState extends State<McpView> {
  late Future<Set<String>> _customIds = widget.controller.customMcpIds();

  void _reload() {
    final Future<Set<String>> customIds = widget.controller.customMcpIds();
    setState(() {
      _customIds = customIds;
    });
  }

  Future<void> _add() async {
    final McpServerDefinition? server = await showDialog<McpServerDefinition>(context: context, builder: (BuildContext context) => const _AddMcpServerDialog());
    if (server != null) {
      await widget.controller.saveMcpServer(server);
      _reload();
    }
  }

  Future<void> _remove(String id) async {
    await widget.controller.removeMcpServer(id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return FutureBuilder<Set<String>>(
      future: _customIds,
      builder: (BuildContext context, AsyncSnapshot<Set<String>> snapshot) {
        final Set<String> customIds = snapshot.data ?? const <String>{};
        return ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text('MCP servers', style: theme.textTheme.headlineSmall)),
                FilledButton.icon(key: const Key('add-mcp'), onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add server')),
              ],
            ),
            const SizedBox(height: 8),
            Text('Agents in a workflow can use these servers, for example to read a Figma design. Weave offers a server when a request contains a link it handles.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            SelectableText(mcpFilePath(widget.controller.services.paths), style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Menlo')),
            const SizedBox(height: 16),
            for (final McpServerDefinition server in widget.controller.mcp.servers)
              Card(
                child: ListTile(
                  leading: Icon(server.transport is McpHttpTransport ? Icons.cloud_outlined : Icons.terminal),
                  title: Text('${server.displayName}  (${server.id})'),
                  subtitle: Text(<String>[_describeTransport(server.transport), if (server.setupHint case final String hint) hint].join('\n')),
                  isThreeLine: server.setupHint != null,
                  trailing: customIds.contains(server.id) ? IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline), onPressed: () => _remove(server.id)) : const Text('Built-in'),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _describeTransport(McpTransport transport) => switch (transport) {
    McpHttpTransport(:final String url) => url,
    McpStdioTransport(:final String command, :final List<String> arguments) => <String>[command, ...arguments].join(' '),
  };
}

class _AddMcpServerDialog extends StatefulWidget {
  const _AddMcpServerDialog();

  @override
  State<_AddMcpServerDialog> createState() => _AddMcpServerDialogState();
}

class _AddMcpServerDialogState extends State<_AddMcpServerDialog> {
  final TextEditingController _id = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _endpoint = TextEditingController();
  final TextEditingController _values = TextEditingController();
  final TextEditingController _links = TextEditingController();
  bool _isHttp = true;
  String? _error;

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[_id, _name, _endpoint, _values, _links]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    try {
      final Map<String, String> values = <String, String>{};
      for (final String line in _values.text.split('\n')) {
        if (line.trim().isEmpty) {
          continue;
        }
        final int separator = line.indexOf('=');
        if (separator <= 0) {
          throw const FormatException('Each header or variable must look like NAME=value.');
        }
        values[line.substring(0, separator).trim()] = line.substring(separator + 1).trim();
      }
      final List<String> command = _isHttp ? const <String>[] : splitCommandLine(_endpoint.text);
      if (!_isHttp && command.isEmpty) {
        throw const FormatException('Enter the command that starts the server.');
      }
      final String id = _id.text.trim();
      Navigator.of(context).pop(
        McpServerDefinition(
          id: id,
          displayName: _name.text.trim().isEmpty ? id : _name.text.trim(),
          transport: _isHttp ? McpHttpTransport(url: _endpoint.text, headers: values) : McpStdioTransport(command: command.first, arguments: command.skip(1).toList(), environment: values),
          linkPatterns: <String>[
            for (final String line in _links.text.split('\n'))
              if (line.trim().isNotEmpty) line.trim(),
          ],
        ),
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    } on ArgumentError catch (error) {
      setState(() => _error = '${error.name ?? 'Value'} ${error.message}');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add MCP server'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('HTTP'), icon: Icon(Icons.cloud_outlined)),
                ButtonSegment<bool>(value: false, label: Text('Command (stdio)'), icon: Icon(Icons.terminal)),
              ],
              selected: <bool>{_isHttp},
              onSelectionChanged: (Set<bool> selection) => setState(() => _isHttp = selection.single),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('mcp-id'),
              controller: _id,
              decoration: const InputDecoration(labelText: 'ID', hintText: 'e.g. linear', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('mcp-endpoint'),
              controller: _endpoint,
              decoration: InputDecoration(labelText: _isHttp ? 'URL' : 'Command', hintText: _isHttp ? 'https://mcp.example.com/mcp' : 'npx -y some-mcp-server', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _values,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: _isHttp ? 'Headers (NAME=value per line)' : 'Environment (NAME=value per line)', helperText: r'Use ${VAR} to read a token from the environment instead of saving it.', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _links,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Link patterns (regular expression per line)', helperText: 'Weave offers this server when a request contains a matching link.', border: OutlineInputBorder()),
            ),
            if (_error case final String error)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      FilledButton(key: const Key('save-mcp'), onPressed: _submit, child: const Text('Save')),
    ],
  );
}
