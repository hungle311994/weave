import 'package:weave_workflow/weave_workflow.dart';

Future<void> main() async {
  final WeaveServices services = await WeaveServices.open();
  print('Agents: ${services.agents.ids.join(', ')}');
  print('MCP servers: ${services.mcp.ids.join(', ')}');
}
