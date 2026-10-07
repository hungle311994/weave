import 'package:flutter/foundation.dart';

import '../domain/onboarding_repository.dart';

/// Owns the first-run flow without introducing a mandatory Weave account.
final class OnboardingController extends ChangeNotifier {
  OnboardingController(this._repository);

  final OnboardingRepository _repository;

  bool _completed = false;
  bool _showAgentSetup = false;
  bool _saving = false;
  String? _error;

  bool get completed => _completed;
  bool get showAgentSetup => _showAgentSetup;
  bool get saving => _saving;
  String? get error => _error;

  Future<void> initialize() async {
    _completed = await _repository.isCompleted();
    notifyListeners();
  }

  void continueLocally() {
    _showAgentSetup = true;
    _error = null;
    notifyListeners();
  }

  void back() {
    _showAgentSetup = false;
    _error = null;
    notifyListeners();
  }

  Future<void> finish() async {
    if (_saving) {
      return;
    }
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.markCompleted();
      _completed = true;
    } on Object {
      _error = 'Weave could not save the setup state. Try again.';
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
