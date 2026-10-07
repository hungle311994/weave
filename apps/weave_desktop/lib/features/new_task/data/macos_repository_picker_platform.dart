import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/repository_picker_platform.dart';

/// macOS bridge for choosing or dropping a repository directory.
final class MacosRepositoryPickerPlatform implements RepositoryPickerPlatform {
  MacosRepositoryPickerPlatform({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('weave/repository_picker') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;
  final StreamController<String> _droppedDirectories = StreamController<String>.broadcast();
  final StreamController<bool> _dragHovering = StreamController<bool>.broadcast();

  @override
  Stream<String> get droppedDirectories => _droppedDirectories.stream;

  @override
  Stream<bool> get dragHovering => _dragHovering.stream;

  @override
  Future<String?> chooseDirectory() async {
    try {
      return await _channel.invokeMethod<String>('chooseDirectory');
    } on MissingPluginException {
      throw const DirectoryPickerUnavailableException('the native picker is not registered');
    } on PlatformException catch (error) {
      throw DirectoryPickerUnavailableException(error.message ?? error.code);
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final Object? arguments = call.arguments;
    if (call.method == 'repositoryDropped' && arguments is String && arguments.trim().isNotEmpty) {
      _droppedDirectories.add(arguments);
    } else if (call.method == 'repositoryDragging' && arguments is bool) {
      _dragHovering.add(arguments);
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _droppedDirectories.close();
    _dragHovering.close();
  }
}
