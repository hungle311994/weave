import 'package:weave_workflow/weave_workflow.dart';

/// A validated Git repository and the workflow defaults loaded for it.
final class LoadedRepository {
  const LoadedRepository({required this.root, required this.branch, required this.settings});

  final String root;
  final String? branch;
  final WorkflowSettings settings;
}
