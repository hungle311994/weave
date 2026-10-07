import 'dart:io';

import 'package:flutter/foundation.dart';

import 'preferences/sidebar_preference_store.dart';

/// What the main pane shows.
sealed class AppDestination {
  const AppDestination();
}

/// The form for starting a workflow.
final class NewTaskDestination extends AppDestination {
  const NewTaskDestination();
}

/// The installed-agent list.
final class AgentsDestination extends AppDestination {
  const AgentsDestination();
}

/// Plugins, skills, and installed extensions.
final class PluginsDestination extends AppDestination {
  const PluginsDestination();
}

/// The read-only security and workflow policy.
final class SettingsDestination extends AppDestination {
  const SettingsDestination();
}

/// A workflow identified by [taskId].
final class WorkflowDestination extends AppDestination {
  const WorkflowDestination(this.taskId);

  final String taskId;

  @override
  bool operator ==(Object other) => other is WorkflowDestination && other.taskId == taskId;

  @override
  int get hashCode => taskId.hashCode;
}

/// Owns top-level navigation and the persisted contextual-sidebar preference.
final class AppController extends ChangeNotifier {
  AppController(this._sidebarPreferences, {required this.userName});

  final SidebarPreferenceStore _sidebarPreferences;

  /// The current macOS account name shown at the foot of the sidebar.
  final String userName;

  AppDestination _destination = const NewTaskDestination();
  bool? _sidebarExpanded;

  /// Destinations left with [select], newest last, and those left with
  /// [goBack], newest last; like a browser's history.
  final List<AppDestination> _back = <AppDestination>[];
  final List<AppDestination> _forward = <AppDestination>[];

  AppDestination get destination => _destination;

  /// Loads the explicit sidebar choice, if one was saved previously.
  Future<void> initialize() async {
    _sidebarExpanded = await _sidebarPreferences.readExpanded();
    notifyListeners();
  }

  /// Whether the contextual sub-sidebar is visible. It starts visible.
  bool get sidebarExpanded => _sidebarExpanded ?? true;

  /// Shows or hides the contextual sub-sidebar and remembers that choice.
  Future<void> toggleSidebar() => setSidebarExpanded(!sidebarExpanded);

  /// Sets the contextual sub-sidebar state and remembers that choice.
  Future<void> setSidebarExpanded(bool expanded) async {
    if (_sidebarExpanded == expanded) {
      return;
    }
    _sidebarExpanded = expanded;
    notifyListeners();
    try {
      await _sidebarPreferences.writeExpanded(expanded);
    } on FileSystemException {
      // Preference persistence must never make navigation unusable.
    }
  }

  bool get canGoBack => _back.isNotEmpty;

  bool get canGoForward => _forward.isNotEmpty;

  /// Shows [destination] and records the current one for [goBack]; choosing
  /// the destination already shown changes nothing.
  void select(AppDestination destination) {
    if (_sameDestination(destination, _destination)) {
      return;
    }
    _back.add(_destination);
    _forward.clear();
    _destination = destination;
    notifyListeners();
  }

  /// Returns to the previously shown destination.
  void goBack() {
    if (_back.isEmpty) {
      return;
    }
    _forward.add(_destination);
    _destination = _back.removeLast();
    notifyListeners();
  }

  /// Undoes the last [goBack].
  void goForward() {
    if (_forward.isEmpty) {
      return;
    }
    _back.add(_destination);
    _destination = _forward.removeLast();
    notifyListeners();
  }

  /// Drops a deleted workflow from the history so Back never opens it, then
  /// leaves it if it is shown.
  void forgetWorkflow(String taskId) {
    bool deleted(AppDestination destination) => destination == WorkflowDestination(taskId);
    _back.removeWhere(deleted);
    _forward.removeWhere(deleted);
    if (deleted(_destination)) {
      _destination = _back.isEmpty ? const NewTaskDestination() : _back.removeLast();
    }
    // Two neighbours, or a neighbour and the shown page, may now be the same page.
    for (final List<AppDestination> stack in <List<AppDestination>>[_back, _forward]) {
      for (int index = stack.length - 1; index > 0; index--) {
        if (_sameDestination(stack[index], stack[index - 1])) {
          stack.removeAt(index);
        }
      }
      while (stack.isNotEmpty && _sameDestination(stack.last, _destination)) {
        stack.removeLast();
      }
    }
    notifyListeners();
  }

  /// Pages without parameters are equal by kind; workflows by task ID.
  static bool _sameDestination(AppDestination a, AppDestination b) => a is WorkflowDestination ? a == b : a.runtimeType == b.runtimeType;
}
