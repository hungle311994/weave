/// The lifecycle state of a Weave workflow.
enum WorkflowStatus {
  pending,
  planning,
  readyForImplementation,
  implementing,
  readyForReview,
  reviewing,
  changesRequested,
  completed,
  failed,
  cancelled;

  /// Whether this status ends the workflow lifecycle.
  bool get isTerminal => switch (this) {
    completed || failed || cancelled => true,
    _ => false,
  };
}
