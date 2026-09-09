import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/mac_widgets.dart';
import '../widgets/sidebar.dart';
import '../widgets/title_bar.dart';
import 'accounts_screen.dart';
import 'activity_screen.dart';
import 'dashboard_screen.dart';
import 'help_screen.dart';
import 'recorder_screen.dart';
import 'script_detail_screen.dart';
import 'scripts_screen.dart';
import 'settings_screen.dart';

/// The whole window: title bar on top, sidebar on the (RTL) right.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();
    _showErrors(context, state);

    return Scaffold(
      backgroundColor: mac.content,
      body: Column(
        children: [
          MacTitleBar(
            title: _title(state),
            subtitle: _subtitle(state),
            actions: _actions(context, state),
          ),
          Expanded(
            child: state.booting
                ? const _Booting()
                : (!state.connected
                    ? _Disconnected(state: state)
                    : Row(
                        children: [
                          const MacSidebar(),
                          Expanded(child: _Content(state: state)),
                        ],
                      )),
          ),
        ],
      ),
    );
  }

  String _title(AppState state) {
    if (state.selected != null && state.page == AppPage.scripts) {
      return state.selected!.name;
    }
    switch (state.page) {
      case AppPage.dashboard:
        return 'داشبورډ';
      case AppPage.scripts:
        return 'سکریپټونه';
      case AppPage.accounts:
        return 'اکاونټونه';
      case AppPage.recorder:
        return 'ثبتونکی';
      case AppPage.activity:
        return 'پېښې';
      case AppPage.settings:
        return 'تنظیمات';
      case AppPage.help:
        return 'مرسته';
    }
  }

  String? _subtitle(AppState state) {
    if (state.session == SessionState.loggingIn) return '— ننوتل روان دي';
    if (state.session == SessionState.recording) return '— ثبتول روان دي';
    if (state.session == SessionState.playing) {
      final total = state.totalSteps;
      if (total != null) return '— ${state.currentStep ?? 0}/$total';
      return '— روان دی';
    }
    return null;
  }

  List<Widget> _actions(BuildContext context, AppState state) {
    if (!state.connected) return const [];
    return [
      MacIconButton(
        icon: Icons.refresh_rounded,
        tooltip: 'تازه کول',
        onPressed: state.refresh,
      ),
      Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        color: MacPalette.of(context).hairline,
      ),
      if (state.session == SessionState.loggingIn)
        MacButton(
          label: 'ننوتم',
          icon: Icons.check_rounded,
          style: MacButtonStyle.primary,
          onPressed: state.finishLogin,
        )
      else if (state.session == SessionState.recording)
        MacButton(
          label: 'ثبتول ودروه',
          icon: Icons.stop_rounded,
          style: MacButtonStyle.danger,
          onPressed: state.stopRecording,
        )
      else if (state.session == SessionState.playing)
        MacButton(
          label: 'ودروه',
          icon: Icons.stop_rounded,
          onPressed: state.stopSession,
        )
      else
        MacButton(
          label: 'ثبتول',
          icon: Icons.fiber_manual_record,
          onPressed: () => startRecordingFlow(context),
        ),
    ];
  }

  void _showErrors(BuildContext context, AppState state) {
    final error = state.consumeError();
    if (error == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final mac = MacPalette.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error, style: const TextStyle(fontSize: 13)),
          backgroundColor: mac.red,
          behavior: SnackBarBehavior.floating,
          width: 520,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    });
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    Widget child;

    if (state.page == AppPage.scripts && state.selected != null) {
      child = const ScriptDetailScreen(key: ValueKey('detail'));
    } else {
      switch (state.page) {
        case AppPage.dashboard:
          child = const DashboardScreen(key: ValueKey('dashboard'));
          break;
        case AppPage.scripts:
          child = const ScriptsScreen(key: ValueKey('scripts'));
          break;
        case AppPage.accounts:
          child = const AccountsScreen(key: ValueKey('accounts'));
          break;
        case AppPage.recorder:
          child = const RecorderScreen(key: ValueKey('recorder'));
          break;
        case AppPage.activity:
          child = const ActivityScreen(key: ValueKey('activity'));
          break;
        case AppPage.settings:
          child = const SettingsScreen(key: ValueKey('settings'));
          break;
        case AppPage.help:
          child = const HelpScreen(key: ValueKey('help'));
          break;
      }
    }

    return Container(
      color: mac.content,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        transitionBuilder: (widget, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.012),
              end: Offset.zero,
            ).animate(animation),
            child: widget,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _Booting extends StatelessWidget {
  const _Booting();

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: mac.accent),
          ),
          const SizedBox(height: 18),
          Text('د سرور سره نښلېدل…',
              style: TextStyle(fontSize: 13, color: mac.text2)),
        ],
      ),
    );
  }
}

class _Disconnected extends StatelessWidget {
  const _Disconnected({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Center(
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: mac.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.cloud_off_rounded, size: 30, color: mac.red),
            ),
            const SizedBox(height: 16),
            Text('د Python سرور سره اړیکه ونه شوه',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              state.connectionError ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: mac.text2, height: 1.6),
            ),
            const SizedBox(height: 6),
            Text(
              'لومړی scripts\\setup.ps1 وچلوئ، بیا دا برنامه بیا پیل کړئ.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: mac.text2),
            ),
            const SizedBox(height: 18),
            MacButton(
              label: 'بیا هڅه',
              icon: Icons.refresh_rounded,
              style: MacButtonStyle.primary,
              large: true,
              onPressed: state.retryConnection,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared page scaffolding: big title, subtitle and trailing actions.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: TextStyle(fontSize: 13, color: mac.text2)),
                ],
              ],
            ),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// Standard content padding used by every page.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
      child: child,
    );
  }
}
