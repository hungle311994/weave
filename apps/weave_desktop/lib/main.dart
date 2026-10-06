import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:weave_workflow/weave_workflow.dart';

import 'src/weave_app.dart';
import 'src/weave_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(<String>['Poppins'], await rootBundle.loadString('assets/fonts/poppins/OFL.txt'));
  });
  runApp(
    WeaveApp(
      createController: () async => WeaveController(
        await WeaveServices.open(),
      ),
    ),
  );
}
