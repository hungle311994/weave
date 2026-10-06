import 'package:weave_storage/weave_storage.dart';

void main() {
  final WeaveStoragePaths paths = WeaveStoragePaths.current();
  print('Weave data: ${paths.rootDirectory}');
}
