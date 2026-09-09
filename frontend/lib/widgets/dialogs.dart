import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/script.dart';
import '../models/settings.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import 'mac_widgets.dart';

/// A macOS sheet: drops from the top of the window, no rounded-bottom dialog.
Future<T?> showMacSheet<T>(BuildContext context, Widget child) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'sheet',
    barrierColor: Colors.black.withOpacity(0.18),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, _, __) {
      final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 78),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero)
                .animate(curve),
            child: FadeTransition(
              opacity: curve,
              child: Material(
                color: Colors.transparent,
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class MacSheet extends StatelessWidget {
  const MacSheet({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.width = 480,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final IconData? icon;
  final Color? iconColor;
  final double width;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: mac.window,
        borderRadius: BorderRadius.circular(MacRadius.sheet),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.32),
            blurRadius: 50,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: iconColor ?? mac.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 17, color: Colors.white),
                      ),
                      const SizedBox(width: 11),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: mac.text)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(subtitle!,
                                style: TextStyle(fontSize: 12.5, color: mac.text2)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                body,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Row(children: actions),
          ),
        ],
      ),
    );
  }
}

class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: MacPalette.of(context).text2)),
    );
  }
}

// --------------------------------------------------------------- record flow

class _RecordResult {
  _RecordResult(this.name, this.url, this.captureScroll, this.browser);

  final String name;
  final String url;
  final bool captureScroll;
  final String browser;
}

/// Asks for a name, a start page and a browser, then starts recording.
Future<void> startRecordingFlow(BuildContext context) async {
  final state = context.read<AppState>();
  final result = await showMacSheet<_RecordResult>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const _RecordSheet(),
    ),
  );
  if (result == null) return;
  await state.startRecording(
    name: result.name,
    url: result.url,
    captureScroll: result.captureScroll,
    browser: result.browser,
  );
}

class _RecordSheet extends StatefulWidget {
  const _RecordSheet();

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  final _name = TextEditingController(text: 'نوی سکریپټ');
  final _url = TextEditingController(text: 'https://www.facebook.com');
  bool _captureScroll = false;
  String _browser = 'auto';
  String? _error;

  @override
  void initState() {
    super.initState();
    _captureScroll = context.read<AppState>().settings.captureScroll;
    _browser = context.read<AppState>().settings.browser;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    final uri = Uri.tryParse(url);
    if (name.isEmpty) {
      setState(() => _error = 'نوم اړین دی');
      return;
    }
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      setState(() => _error = 'سمه پته ولیکئ (https:// سره)');
      return;
    }
    Navigator.of(context).pop(_RecordResult(name, url, _captureScroll, _browser));
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();

    return MacSheet(
      title: 'نوې لارښوونه ثبتول',
      subtitle: 'براوزر پرانیستل کېږي — خپل کار پکې وکړئ',
      icon: Icons.fiber_manual_record,
      iconColor: mac.red,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetLabel('د سکریپټ نوم'),
          MacField(controller: _name, autofocus: true),
          const SizedBox(height: 13),
          const SheetLabel('پیل پته'),
          MacField(controller: _url, onSubmitted: (_) => _submit()),
          const SizedBox(height: 13),
          const SheetLabel('براوزر'),
          _BrowserPicker(
            value: _browser,
            browsers: state.browsers,
            onChanged: (value) => setState(() => _browser = value),
          ),
          const SizedBox(height: 6),
          MacRow(
            title: 'سکرول هم ثبت کړه',
            subtitle: 'ډېری وخت اړتیا نشته',
            trailing: MacSwitch(
              value: _captureScroll,
              onChanged: (value) => setState(() => _captureScroll = value),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(fontSize: 12, color: mac.red)),
            ),
        ],
      ),
      actions: [
        MacButton(
          label: 'ثبتول پیل کړه',
          icon: Icons.fiber_manual_record,
          style: MacButtonStyle.danger,
          large: true,
          onPressed: _submit,
        ),
        const SizedBox(width: 10),
        MacButton(
          label: 'لغوه',
          large: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Dropdown listing only the browsers that are really installed.
class _BrowserPicker extends StatelessWidget {
  const _BrowserPicker({
    required this.value,
    required this.browsers,
    required this.onChanged,
  });

  final String value;
  final BrowserList browsers;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final installed = browsers.installed;
    final active = browsers.activeBrowser;

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: mac.window,
        borderRadius: BorderRadius.circular(MacRadius.control),
        border: Border.all(color: mac.hairline, width: 0.8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          icon: Icon(Icons.unfold_more_rounded, size: 15, color: mac.text3),
          style: TextStyle(fontSize: 13, color: mac.text),
          dropdownColor: mac.window,
          items: [
            DropdownMenuItem(
              value: 'auto',
              child: Row(
                children: [
                  StatusDot(color: active == null ? mac.orange : mac.green),
                  const SizedBox(width: 8),
                  Text(active == null
                      ? 'اتوماتیک (براوزر ونه موندل شو)'
                      : 'اتوماتیک — ${active.name}'),
                ],
              ),
            ),
            ...installed.map(
              (browser) => DropdownMenuItem(
                value: browser.id,
                child: Row(
                  children: [
                    StatusDot(color: mac.green),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        browser.shortVersion.isEmpty
                            ? browser.name
                            : '${browser.name} ${browser.shortVersion}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ run flow

/// Asks for the script's variables. Returns an empty map when it has none,
/// and null when the user cancelled.
Future<Map<String, String>?> collectVariables(
    BuildContext context, WebScript script) async {
  if (script.variables.isEmpty) return const {};
  return showMacSheet<Map<String, String>>(
    context,
    _VariablesSheet(variables: script.variables, scriptName: script.name),
  );
}

/// Collects any secret variables, then starts the run with saved defaults.
Future<void> runScriptFlow(BuildContext context, WebScript script) async {
  final state = context.read<AppState>();
  final variables = await collectVariables(context, script);
  if (variables == null) return;
  await state.runScript(script.id, variables: variables);
}

class _VariablesSheet extends StatefulWidget {
  const _VariablesSheet({required this.variables, required this.scriptName});

  final List<VariableModel> variables;
  final String scriptName;

  @override
  State<_VariablesSheet> createState() => _VariablesSheetState();
}

class _VariablesSheetState extends State<_VariablesSheet> {
  late final Map<String, TextEditingController> _controllers = {
    for (final variable in widget.variables)
      variable.name: TextEditingController(text: variable.defaultValue),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return MacSheet(
      title: 'اړین ارزښتونه',
      subtitle: widget.scriptName,
      icon: Icons.lock_outline_rounded,
      iconColor: mac.orange,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final variable in widget.variables) ...[
            SheetLabel(variable.label.isEmpty
                ? variable.name
                : '${variable.label} (${variable.name})'),
            MacField(
              controller: _controllers[variable.name],
              obscure: variable.secret,
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'دا ارزښتونه یوازې د چلولو لپاره کارېږي او فایل ته نه لیکل کېږي.',
            style: TextStyle(fontSize: 11.5, color: mac.text2, height: 1.5),
          ),
        ],
      ),
      actions: [
        MacButton(
          label: 'چلول',
          icon: Icons.play_arrow_rounded,
          style: MacButtonStyle.primary,
          large: true,
          onPressed: () => Navigator.of(context).pop(
            _controllers.map((key, value) => MapEntry(key, value.text)),
          ),
        ),
        const SizedBox(width: 10),
        MacButton(
          label: 'لغوه',
          large: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- simple input

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String initialValue,
  String label = '',
  String? subtitle,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showMacSheet<String>(
    context,
    Builder(
      builder: (context) => MacSheet(
        title: title,
        subtitle: subtitle,
        icon: Icons.edit_outlined,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label.isNotEmpty) SheetLabel(label),
            MacField(
              controller: controller,
              autofocus: true,
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
        actions: [
          MacButton(
            label: 'خوندي کول',
            style: MacButtonStyle.primary,
            large: true,
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
          const SizedBox(width: 10),
          MacButton(
            label: 'لغوه',
            large: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

/// Creates an empty script and opens it.
Future<void> newEmptyScriptFlow(BuildContext context) async {
  final state = context.read<AppState>();
  final name = await promptText(
    context,
    title: 'نوی سکریپټ',
    subtitle: 'تش سکریپټ جوړېږي — ګامونه یې وروسته ثبت کړئ',
    initialValue: 'نوی سکریپټ',
    label: 'نوم',
  );
  if (name == null || name.trim().isEmpty) return;
  final script = await state.createScript(name.trim(), '');
  if (script != null) await state.openScript(script.id);
}

Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'هو',
  bool destructive = true,
}) async {
  final result = await showMacSheet<bool>(
    context,
    Builder(
      builder: (context) {
        final mac = MacPalette.of(context);
        return MacSheet(
          title: title,
          icon: Icons.warning_amber_rounded,
          iconColor: destructive ? mac.red : mac.orange,
          width: 430,
          body: Text(
            message,
            style: TextStyle(fontSize: 13, color: mac.text2, height: 1.6),
          ),
          actions: [
            MacButton(
              label: confirmLabel,
              style: destructive ? MacButtonStyle.danger : MacButtonStyle.primary,
              large: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(width: 10),
            MacButton(
              label: 'نه',
              large: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        );
      },
    ),
  );
  return result ?? false;
}
