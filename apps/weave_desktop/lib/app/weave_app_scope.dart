import 'package:path/path.dart' as path;
import 'package:weave_agents/weave_agents.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../features/agents/data/macos_terminal_launcher.dart';
import '../features/agents/data/weave_agents_repository.dart';
import '../features/agents/domain/terminal_launcher.dart';
import '../features/agents/presentation/agents_controller.dart';
import '../features/integrations/data/weave_integrations_repository.dart';
import '../features/integrations/presentation/integrations_controller.dart';
import '../features/new_task/data/weave_new_task_repository.dart';
import '../features/new_task/data/macos_repository_picker_platform.dart';
import '../features/new_task/domain/repository_picker_platform.dart';
import '../features/new_task/presentation/new_task_controller.dart';
import '../features/onboarding/data/file_onboarding_repository.dart';
import '../features/onboarding/presentation/onboarding_controller.dart';
import '../features/workflow_run/data/weave_workflow_repository.dart';
import '../features/workflow_run/presentation/workflow_controller.dart';
import 'app_controller.dart';
import 'preferences/sidebar_preference_store.dart';
import 'window/window_chrome.dart';

/// Controllers and repositories composed for one running desktop app.
final class WeaveAppScope {
  WeaveAppScope._({required this.app, required this.agents, required this.integrations, required this.newTask, required this.onboarding, required this.repositoryPicker, required this.workflow, required this.windowChrome});

  /// Reads where macOS draws the window controls.
  final WindowChrome windowChrome;

  /// Where macOS centres the traffic lights, read once at start-up.
  double? trafficLightCenter;

  final AppController app;
  final AgentsController agents;
  final IntegrationsController integrations;
  final NewTaskController newTask;
  final OnboardingController onboarding;
  final RepositoryPickerPlatform repositoryPicker;
  final WorkflowController workflow;

  /// Creates the production scope over [services].
  static WeaveAppScope create(WeaveServices services, {VerificationRunner? verifier, RepositoryPickerPlatform? repositoryPicker, TerminalLauncher? terminal, McpRegistryClient? mcpRegistry, WindowChrome windowChrome = const MacosWindowChrome()}) {
    final String userName = services.environment['USER']?.trim().isNotEmpty == true ? services.environment['USER']!.trim() : 'User';
    final AppController app = AppController(FileSidebarPreferenceStore(services.paths.rootDirectory), userName: userName);
    final AgentsController agents = AgentsController(WeaveAgentsRepository(services, terminal ?? MacosTerminalLauncher(path.join(services.paths.rootDirectory, 'sign-in'))));
    final IntegrationsController integrations = IntegrationsController(WeaveIntegrationsRepository(services, registry: mcpRegistry));
    final OnboardingController onboarding = OnboardingController(FileOnboardingRepository(services.paths.rootDirectory));
    late final WorkflowController workflow;
    workflow = WorkflowController(
      WeaveWorkflowRepository(services, verifier: verifier),
      onWorkflowSelected: (String taskId) => app.select(WorkflowDestination(taskId)),
      onWorkflowDeleted: app.forgetWorkflow,
    );
    final NewTaskController newTask = NewTaskController(WeaveNewTaskRepository(services, verifier: verifier), onStarted: workflow.track);
    return WeaveAppScope._(
      app: app,
      agents: agents,
      integrations: integrations,
      newTask: newTask,
      onboarding: onboarding,
      repositoryPicker: repositoryPicker ?? MacosRepositoryPickerPlatform(),
      workflow: workflow,
      windowChrome: windowChrome,
    );
  }

  Future<void> initialize() => Future.wait(<Future<void>>[app.initialize(), agents.refresh(), onboarding.initialize(), workflow.initialize(), windowChrome.trafficLightCenter().then((double? center) => trafficLightCenter = center)]);

  void dispose() {
    repositoryPicker.dispose();
    workflow.dispose();
    integrations.dispose();
    agents.dispose();
    onboarding.dispose();
    app.dispose();
  }
}
