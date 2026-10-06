import 'package:flutter/material.dart';

import '../core/design_system/design_system.dart';
import 'views/agents_view.dart';
import 'views/mcp_view.dart';
import 'views/new_workflow_view.dart';
import 'views/sidebar.dart';
import 'views/workflow_view.dart';
import 'weave_controller.dart';

/// Root widget; [createController] is injectable for tests.
class WeaveApp extends StatefulWidget {
  const WeaveApp({required this.createController, super.key});

  final Future<WeaveController> Function() createController;

  @override
  State<WeaveApp> createState() => _WeaveAppState();
}

class _WeaveAppState extends State<WeaveApp> {
  late final Future<WeaveController> _controller = () async {
    final WeaveController controller = await widget.createController();
    await controller.initialize();
    return controller;
  }();

  @override
  void dispose() {
    _controller.then((WeaveController controller) => controller.dispose(), onError: (Object _) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weave',
      debugShowCheckedModeBanner: false,
      theme: WeaveTheme.dark(),
      themeMode: ThemeMode.dark,
      home: FutureBuilder<WeaveController>(
        future: _controller,
        builder: (BuildContext context, AsyncSnapshot<WeaveController> snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: SelectableText('Weave could not start:\n\n${snapshot.error}', textAlign: TextAlign.center),
                ),
              ),
            );
          }
          final WeaveController? controller = snapshot.data;
          if (controller == null) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return WeaveHome(controller: controller);
        },
      ),
    );
  }
}

/// Sidebar plus the selected view.
class WeaveHome extends StatelessWidget {
  const WeaveHome({required this.controller, super.key});

  final WeaveController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(width: 280, child: Sidebar(controller: controller)),
          const VerticalDivider(width: 1),
          Expanded(
            child: switch (controller.selection) {
              NewWorkflowSelection() => NewWorkflowView(controller: controller),
              AgentsSelection() => AgentsView(controller: controller),
              McpSelection() => McpView(controller: controller),
              WorkflowSelection(:final String taskId) => WorkflowView(key: ValueKey<String>(taskId), controller: controller, taskId: taskId),
            },
          ),
        ],
      ),
    ),
  );
}
