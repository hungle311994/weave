import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weave/core/design_system/design_system.dart';

void main() {
  group('WeaveTheme.dark', () {
    final ThemeData theme = WeaveTheme.dark();

    test('is dark, uses Poppins and the design canvas', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, WeaveColors.canvas);
      expect(theme.textTheme.bodyMedium?.fontFamily, WeaveTypography.fontFamily);
      expect(theme.colorScheme.primary, WeaveColors.purple);
      expect(theme.colorScheme.onSurface, WeaveColors.textPrimary);
      expect(theme.colorScheme.outline, WeaveColors.border);
    });

    test('maps the type scale from the Figma spec', () {
      expect(theme.textTheme.displaySmall, isA<TextStyle>().having((TextStyle style) => style.fontSize, 'size', 34).having((TextStyle style) => style.fontWeight, 'weight', FontWeight.w700));
      expect(theme.textTheme.titleLarge?.fontSize, 20);
      expect(theme.textTheme.titleMedium?.fontSize, 17);
      expect(theme.textTheme.labelLarge, isA<TextStyle>().having((TextStyle style) => style.fontSize, 'size', 13).having((TextStyle style) => style.fontWeight, 'weight', FontWeight.w600));
      expect(theme.textTheme.bodyLarge?.color, WeaveColors.textSecondary);
    });

    test('draws controls with the design radius and height', () {
      final OutlineInputBorder border = theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
      expect(border.borderRadius, WeaveRadii.controlAll);
      expect(border.borderSide.color, WeaveColors.border);
      expect(theme.outlinedButtonTheme.style?.minimumSize?.resolve(<WidgetState>{}), const Size(0, WeaveLayout.controlHeight));
    });
  });

  test('every text style draws lines at 1.5× in Poppins', () {
    final List<TextStyle> styles = <TextStyle>[
      WeaveTypography.display,
      WeaveTypography.titleLarge,
      WeaveTypography.titleMedium,
      WeaveTypography.titleSmall,
      WeaveTypography.label,
      WeaveTypography.bodyLarge,
      WeaveTypography.bodyStrong,
      WeaveTypography.body,
      WeaveTypography.bodySmall,
      WeaveTypography.breadcrumb,
      WeaveTypography.caption,
      WeaveTypography.overline,
      WeaveTypography.micro,
      WeaveTypography.code,
    ];
    for (final TextStyle style in styles) {
      expect(style.fontFamily, WeaveTypography.fontFamily);
      expect(style.height, 1.5);
    }
  });

  test('tint helpers use the 10 % fill and 35 % border of status pills', () {
    expect(WeaveColors.tint(WeaveColors.green).a, closeTo(0.1, 0.001));
    expect(WeaveColors.tintBorder(WeaveColors.green).a, closeTo(0.35, 0.001));
  });

  test('bundles Poppins 400–700 and its licence', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final String weight in <String>['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final ByteData font = await rootBundle.load('assets/fonts/poppins/Poppins-$weight.ttf');
      expect(font.lengthInBytes, greaterThan(100000), reason: weight);
    }
    expect(await rootBundle.loadString('assets/fonts/poppins/OFL.txt'), contains('SIL Open Font License'));
  });

  testWidgets('text in the app defaults to Poppins on the dark canvas', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeaveTheme.dark(),
        home: const Scaffold(body: Text('Weave')),
      ),
    );
    final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(find.text('Weave'));
    expect(paragraph.text.style?.fontFamily, WeaveTypography.fontFamily);
    expect(tester.widget<Material>(find.byType(Material).first).color, WeaveColors.canvas);
  });
}
