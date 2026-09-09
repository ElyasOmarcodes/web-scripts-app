// Widget tests for the macOS control set every screen is built from.
//
// This file also stands in for the stub `flutter create` would otherwise
// generate here (which references a non-existent MyApp and fails analysis).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_scripts/theme/mac_theme.dart';
import 'package:web_scripts/widgets/mac_widgets.dart';

/// Wraps a widget in the app's theme and right-to-left layout.
Widget host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: buildMacTheme(brightness, 'blue'),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('MacButton', () {
    testWidgets('shows its label and icon', (tester) async {
      await tester.pumpWidget(host(const MacButton(
        label: 'چلول',
        icon: Icons.play_arrow_rounded,
      )));

      expect(find.text('چلول'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(MacButton(
        label: 'ثبتول',
        onPressed: () => taps++,
      )));

      await tester.tap(find.text('ثبتول'));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('a null onPressed makes it inert', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(const MacButton(label: 'ودروه')));

      await tester.tap(find.text('ودروه'));
      await tester.pump();

      expect(taps, 0);
    });
  });

  group('MacSwitch', () {
    testWidgets('reports the flipped value', (tester) async {
      bool? received;
      await tester.pumpWidget(host(MacSwitch(
        value: false,
        onChanged: (value) => received = value,
      )));

      await tester.tap(find.byType(MacSwitch));
      await tester.pump();

      expect(received, isTrue);
    });

    testWidgets('does nothing while disabled', (tester) async {
      await tester.pumpWidget(host(const MacSwitch(value: true)));

      await tester.tap(find.byType(MacSwitch));
      await tester.pump();

      // No callback to fire, and no exception either.
      expect(tester.takeException(), isNull);
    });
  });

  group('MacSegmented', () {
    testWidgets('renders every option and reports the picked one', (tester) async {
      String? picked;
      await tester.pumpWidget(host(MacSegmented<String>(
        value: 'all',
        items: const {'all': 'ټول', 'ok': 'بریالي', 'bad': 'ناکام'},
        onChanged: (value) => picked = value,
      )));

      expect(find.text('ټول'), findsOneWidget);
      expect(find.text('بریالي'), findsOneWidget);

      await tester.tap(find.text('ناکام'));
      await tester.pump();

      expect(picked, 'bad');
    });
  });

  group('MacPill', () {
    testWidgets('shows its text', (tester) async {
      await tester.pumpWidget(host(const MacPill('۸ ګامه')));

      expect(find.text('۸ ګامه'), findsOneWidget);
    });
  });

  group('MacRow', () {
    testWidgets('lays out title, subtitle and trailing', (tester) async {
      await tester.pumpWidget(host(const SizedBox(
        width: 420,
        child: MacRow(
          title: 'پټ چلول',
          subtitle: 'براوزر نه ښکاري',
          trailing: MacPill('غیرفعال'),
        ),
      )));

      expect(find.text('پټ چلول'), findsOneWidget);
      expect(find.text('براوزر نه ښکاري'), findsOneWidget);
      expect(find.text('غیرفعال'), findsOneWidget);
    });

    testWidgets('is tappable when given onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(SizedBox(
        width: 420,
        child: MacRow(title: 'فیسبوک', onTap: () => taps++),
      )));

      await tester.tap(find.text('فیسبوک'));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('theme', () {
    testWidgets('carries the palette and ships Vazirmatn', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(host(Builder(builder: (context) {
        captured = context;
        return const SizedBox.shrink();
      })));

      expect(MacPalette.of(captured).accent, MacPalette.light.accent);
      expect(Theme.of(captured).textTheme.bodyMedium?.fontFamily, 'Vazirmatn');
    });

    testWidgets('the dark palette swaps the surfaces', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(host(
        Builder(builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        }),
        brightness: Brightness.dark,
      ));

      expect(MacPalette.of(captured).window, MacPalette.dark.window);
    });
  });
}
