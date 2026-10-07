/// Persists whether this local Weave installation finished first-run setup.
abstract interface class OnboardingRepository {
  Future<bool> isCompleted();

  Future<void> markCompleted();
}
