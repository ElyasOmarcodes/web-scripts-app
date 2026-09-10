import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/shell.dart';
import 'state/app_state.dart';
import 'theme/mac_theme.dart';

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_isDesktop) {
    // A frameless window; the app draws its own macOS-style title bar.
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1240, 800),
      minimumSize: Size(940, 620),
      center: true,
      title: 'WebScripts',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      backgroundColor: Colors.transparent,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    // The close button must not end the process before the backend has been
    // told to stop; see _CloseGuard below.
    await windowManager.setPreventClose(true);
  }

  runApp(const WebScriptsApp());
}

/// Turns "the user closed the window" into "stop the backend, then close".
class _CloseGuard extends StatefulWidget {
  const _CloseGuard({required this.child});

  final Widget child;

  @override
  State<_CloseGuard> createState() => _CloseGuardState();
}

class _CloseGuardState extends State<_CloseGuard> with WindowListener {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    if (_isDesktop) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await context.read<AppState>().shutdown();
    } catch (_) {
      // Whatever happened, the window still has to close.
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class WebScriptsApp extends StatelessWidget {
  const WebScriptsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..boot(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final accent = state.settings.accent;
          return MaterialApp(
            title: 'WebScripts',
            debugShowCheckedModeBanner: false,
            theme: buildMacTheme(Brightness.light, accent),
            darkTheme: buildMacTheme(Brightness.dark, accent),
            themeMode: _themeMode(state.settings.theme),
            // The whole UI is Pashto, so it is laid out right-to-left.
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
            home: const _CloseGuard(child: AppShell()),
          );
        },
      ),
    );
  }

  ThemeMode _themeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
