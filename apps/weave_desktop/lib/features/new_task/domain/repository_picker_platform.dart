import 'dart:async';

/// Native directory selection and folder-drop events used by New Task.
abstract interface class RepositoryPickerPlatform {
  /// Opens the operating system directory picker; null when the user cancels.
  ///
  /// Throws [DirectoryPickerUnavailableException] when the native picker
  /// cannot be reached.
  Future<String?> chooseDirectory();

  /// Directories dropped onto the application window.
  Stream<String> get droppedDirectories;

  /// True while a folder is dragged over the window, false when it leaves or drops.
  Stream<bool> get dragHovering;

  /// Releases native event subscriptions owned by the implementation.
  void dispose();
}

/// The native directory picker could not be opened, e.g. because the macOS
/// code changed and the app was hot-restarted instead of rebuilt.
final class DirectoryPickerUnavailableException implements Exception {
  const DirectoryPickerUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'DirectoryPickerUnavailableException: $reason';
}
