import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/features/new_task/data/macos_repository_picker_platform.dart';
import 'package:weave/features/new_task/domain/repository_picker_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('weave/repository_picker_test');

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('returns the folder chosen in the native panel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall call) async => call.method == 'chooseDirectory' ? '/projects/weave' : null);
    final MacosRepositoryPickerPlatform platform = MacosRepositoryPickerPlatform(channel: channel);
    addTearDown(platform.dispose);

    expect(await platform.chooseDirectory(), '/projects/weave');
  });

  test('reports an unavailable picker when the native handler is missing, e.g. after a hot restart', () async {
    final MacosRepositoryPickerPlatform platform = MacosRepositoryPickerPlatform(channel: channel);
    addTearDown(platform.dispose);

    await expectLater(platform.chooseDirectory(), throwsA(isA<DirectoryPickerUnavailableException>()));
  });

  test('reports an unavailable picker when the native side fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall call) async => throw PlatformException(code: 'panel', message: 'No window'));
    final MacosRepositoryPickerPlatform platform = MacosRepositoryPickerPlatform(channel: channel);
    addTearDown(platform.dispose);

    await expectLater(platform.chooseDirectory(), throwsA(isA<DirectoryPickerUnavailableException>().having((DirectoryPickerUnavailableException error) => error.reason, 'reason', 'No window')));
  });
}
