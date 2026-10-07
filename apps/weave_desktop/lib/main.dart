import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:weave_workflow/weave_workflow.dart';

import 'app/gallery/component_gallery_page.dart';
import 'app/weave_app.dart';
import 'app/weave_app_scope.dart';
import 'core/design_system/design_system.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(<String>['Poppins'], await rootBundle.loadString('assets/fonts/poppins/OFL.txt'));
  });

  const bool gallery = bool.fromEnvironment('WEAVE_GALLERY');
  if (gallery) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: WeaveTheme.dark(),
        darkTheme: WeaveTheme.dark(),
        themeMode: ThemeMode.dark,
        scrollBehavior: const WeaveScrollBehavior(),
        home: const ComponentGalleryPage(),
      ),
    );
    return;
  }

  runApp(
    WeaveApp(
      createScope: () async => WeaveAppScope.create(
        await WeaveServices.open(),
      ),
    ),
  );
}
