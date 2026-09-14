import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import 'dialogs.dart';
import 'mac_widgets.dart';

/// One proof, for one action.
///
/// Opening the app in the morning is not the same as asking, at four in the
/// afternoon, for a password to be put on the screen or written into a file.
/// Everything that does either comes through here first.
class Proof {
  const Proof(this.code, this.method);

  final String code;

  /// password · windows · biometric
  final String method;
}

Future<Proof?> askForCode(
  BuildContext context, {
  required String title,
  required String reason,
  IconData icon = Icons.lock_outline_rounded,
}) async {
  final state = context.read<AppState>();
  if (!state.security.configured) {
    // Nothing has been locked yet, so there is nothing to ask for.
    return const Proof('', 'password');
  }
  return showMacSheet<Proof>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: _CodeSheet(title: title, reason: reason, icon: icon),
    ),
  );
}

class _CodeSheet extends StatefulWidget {
  const _CodeSheet({
    required this.title,
    required this.reason,
    required this.icon,
  });

  final String title;
  final String reason;
  final IconData icon;

  @override
  State<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends State<_CodeSheet> {
  final _code = TextEditingController();
  String _method = 'password';
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit({String? method}) async {
    final how = method ?? _method;
    final code = how == 'biometric' ? '' : _code.text;
    if (how != 'biometric' && code.isEmpty) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final failure =
        await context.read<AppState>().verifyCode(code: code, method: how);
    if (!mounted) return;
    if (failure == null) {
      Navigator.pop(context, Proof(code, how));
      return;
    }
    setState(() {
      _working = false;
      _error = failure;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final security = context.watch<AppState>().security;

    return MacSheet(
      title: widget.title,
      subtitle: widget.reason,
      icon: widget.icon,
      width: 440,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          MacField(
            controller: _code,
            obscure: true,
            autofocus: true,
            hint: _method == 'windows'
                ? 'د ویندوز پټنوم (${security.windowsUser})'
                : 'د پروګرام پټنوم',
            prefix: Icon(
              _method == 'windows'
                  ? Icons.desktop_windows_outlined
                  : Icons.key_outlined,
              size: 14,
              color: mac.text3,
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 11),
            Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 14, color: mac.red),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(_error!,
                      style: TextStyle(fontSize: 11.5, color: mac.red)),
                ),
              ],
            ),
          ],
          if (security.biometricEnabled || security.windowsEnabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (security.biometricEnabled)
                  MacButton(
                    label: 'د ګوتې نښه',
                    icon: Icons.fingerprint_rounded,
                    onPressed:
                        _working ? null : () => _submit(method: 'biometric'),
                  ),
                if (security.biometricEnabled && security.windowsEnabled)
                  const SizedBox(width: 8),
                if (security.windowsEnabled)
                  MacButton(
                    label: _method == 'windows'
                        ? 'د پروګرام پټنوم'
                        : 'د ویندوز پټنوم',
                    icon: Icons.desktop_windows_outlined,
                    onPressed: _working
                        ? null
                        : () => setState(() {
                              _method =
                                  _method == 'windows' ? 'password' : 'windows';
                              _error = null;
                            }),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        MacButton(label: 'بندول', onPressed: () => Navigator.pop(context)),
        const SizedBox(width: 8),
        MacButton(
          label: _working ? 'کتل کېږي…' : 'تایید',
          style: MacButtonStyle.primary,
          onPressed: _working ? null : () => _submit(),
        ),
      ],
    );
  }
}

/// Type an account's own username and password.
///
/// Reached only after [askForCode] has already said yes, so the fields start
/// filled in with whatever is saved — there is no second wall to climb once
/// the first one has been.
Future<Map<String, String>?> editAccountSecrets(
  BuildContext context,
  Map<String, String> existing,
) async {
  final state = context.read<AppState>();
  return showMacSheet<Map<String, String>>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: _SecretsSheet(existing: existing),
    ),
  );
}

class _SecretsSheet extends StatefulWidget {
  const _SecretsSheet({required this.existing});

  final Map<String, String> existing;

  @override
  State<_SecretsSheet> createState() => _SecretsSheetState();
}

class _SecretsSheetState extends State<_SecretsSheet> {
  late final _username =
      TextEditingController(text: widget.existing['username'] ?? '');
  late final _password =
      TextEditingController(text: widget.existing['password'] ?? '');
  late final _note = TextEditingController(text: widget.existing['note'] ?? '');
  bool _show = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return MacSheet(
      title: 'کارن‌نوم او پټنوم',
      subtitle: 'یوازې ستاسو په کمپیوټر کې، د پروګرام د کیلي لاندې کلپ کېږي.',
      icon: Icons.key_outlined,
      width: 470,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FieldLabel('کارن‌نوم / ایمیل / شمېره'),
          Directionality(
            textDirection: TextDirection.ltr,
            child: MacField(controller: _username, autofocus: true),
          ),
          const SizedBox(height: 13),
          const _FieldLabel('پټنوم'),
          Row(
            children: [
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: MacField(controller: _password, obscure: !_show),
                ),
              ),
              const SizedBox(width: 7),
              MacIconButton(
                icon: _show
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                tooltip: _show ? 'پټ کړه' : 'ښکاره کړه',
                onPressed: () => setState(() => _show = !_show),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const _FieldLabel('یادونه (اختیاري)'),
          MacField(controller: _note, hint: 'لکه: د بیا راګرځولو ایمیل'),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: mac.text3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'پروګرام پخپله دا پټنوم نه کاروي — ننوتل لا هم په کوکیزو '
                  'کېږي. دا هغه ورځ لپاره دی چې کوکیز مړه شي او بیا ننوتل '
                  'وغواړي.',
                  style:
                      TextStyle(fontSize: 11, height: 1.6, color: mac.text3),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        MacButton(label: 'بندول', onPressed: () => Navigator.pop(context)),
        const Spacer(),
        MacButton(
          label: 'ړنګول',
          icon: Icons.delete_outline_rounded,
          style: MacButtonStyle.danger,
          onPressed: () => Navigator.pop(
              context, const {'username': '', 'password': '', 'note': ''}),
        ),
        const SizedBox(width: 8),
        MacButton(
          label: 'ثبتول',
          icon: Icons.check_rounded,
          style: MacButtonStyle.primary,
          onPressed: () => Navigator.pop(context, {
            'username': _username.text.trim(),
            'password': _password.text,
            'note': _note.text.trim(),
          }),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: MacPalette.of(context).text2,
          ),
        ),
      );
}

/// Change the app's password.
///
/// The old one is required — a lock that anybody sitting at an open app can
/// re-key is not a lock — and the new one is typed twice, because a password
/// mistyped once is a password nobody will ever guess, including its owner.
Future<void> changePasswordFlow(BuildContext context) async {
  final state = context.read<AppState>();
  await showMacSheet<void>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const _ChangePasswordSheet(),
    ),
  );
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _working = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    if (_next.text.length < state.security.minLength) {
      setState(() => _error =
          'نوی پټنوم باید لږ تر لږه ${state.security.minLength} تورې ولري.');
      return;
    }
    if (_next.text != _again.text) {
      setState(() => _error = 'دواړه نوي پټنومونه یو شان نه دي.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final failure = await state.changePassword(_current.text, _next.text);
    if (!mounted) return;
    setState(() {
      _working = false;
      _error = failure;
      _done = failure == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final security = context.watch<AppState>().security;

    return MacSheet(
      title: 'پټنوم بدلول',
      subtitle: 'خوندي شوي معلومات پخپل ځای پاتې کېږي — یوازې کولپ بدلېږي.',
      icon: Icons.key_outlined,
      width: 450,
      body: _done
          ? Row(
              children: [
                Icon(Icons.check_circle_outline, size: 17, color: mac.green),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'پټنوم بدل شو. له دې وروسته نوی وکاروئ.',
                    style: TextStyle(fontSize: 12.5, color: mac.text),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _FieldLabel('اوسنی پټنوم'),
                MacField(
                  controller: _current,
                  obscure: true,
                  autofocus: true,
                ),
                const SizedBox(height: 13),
                const _FieldLabel('نوی پټنوم'),
                MacField(
                  controller: _next,
                  obscure: true,
                  hint: 'لږ تر لږه ${security.minLength} تورې',
                ),
                const SizedBox(height: 13),
                const _FieldLabel('نوی پټنوم، بیا'),
                MacField(
                  controller: _again,
                  obscure: true,
                  onSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 14, color: mac.red),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(_error!,
                            style:
                                TextStyle(fontSize: 11.5, color: mac.red)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: mac.text3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        security.windowsEnabled || security.biometricEnabled
                            ? 'د ویندوز پټنوم او د ګوتې نښه لکه پخوا کار کوي.'
                            : 'که دا پټنوم هېر کړئ، خوندي شوي معلومات بیرته '
                                'نه راځي — هېڅ «بیا ترلاسه کول» نشته، ځکه چې '
                                'کیلي یوازې ستاسو په ذهن کې ده.',
                        style: TextStyle(
                            fontSize: 11, height: 1.6, color: mac.text3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
      actions: _done
          ? [
              MacButton(
                label: 'ښه',
                style: MacButtonStyle.primary,
                onPressed: () => Navigator.pop(context),
              ),
            ]
          : [
              MacButton(
                  label: 'بندول', onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 8),
              MacButton(
                label: _working ? 'بدلېږي…' : 'بدل کړه',
                icon: Icons.check_rounded,
                style: MacButtonStyle.primary,
                onPressed: _working ? null : _save,
              ),
            ],
    );
  }
}

/// Switch the Windows-password door on or off.
///
/// Turning it on needs the Windows password, because Windows is what verifies
/// it; turning it off needs nothing but the app already being open, since
/// removing a door never opens one.
Future<void> windowsPasswordFlow(BuildContext context, bool enable) async {
  final state = context.read<AppState>();
  if (!enable) {
    await state.setSecurityMethods(windows: false);
    return;
  }
  final password = await showMacSheet<String>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const _WindowsPasswordSheet(),
    ),
  );
  if (password == null) return;
  final failure =
      await state.setSecurityMethods(windows: true, windowsPassword: password);
  if (failure != null && context.mounted) {
    await showMacSheet<void>(
      context,
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: _Told(message: failure),
      ),
    );
  }
}

class _WindowsPasswordSheet extends StatefulWidget {
  const _WindowsPasswordSheet();

  @override
  State<_WindowsPasswordSheet> createState() => _WindowsPasswordSheetState();
}

class _WindowsPasswordSheetState extends State<_WindowsPasswordSheet> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final security = context.watch<AppState>().security;
    return MacSheet(
      title: 'د کمپیوټر پټنوم',
      subtitle: 'ویندوز پخپله یې کوي — موږ یې نه ساتو.',
      icon: Icons.desktop_windows_outlined,
      width: 440,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FieldLabel('د «${security.windowsUser}» پټنوم'),
          MacField(
            controller: _password,
            obscure: true,
            autofocus: true,
            onSubmitted: (_) => Navigator.pop(context, _password.text),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: mac.text3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'که کله د ویندوز پټنوم بدل کړئ، دا لار به کار ونه کړي — خو '
                  'د پروګرام خپل پټنوم به لکه پخوا پرانیزي یې، نو له خپلو '
                  'اکاونټونو بهر پاتې نه شئ.',
                  style: TextStyle(fontSize: 11, height: 1.6, color: mac.text3),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        MacButton(label: 'بندول', onPressed: () => Navigator.pop(context)),
        const SizedBox(width: 8),
        MacButton(
          label: 'فعاله کړه',
          icon: Icons.check_rounded,
          style: MacButtonStyle.primary,
          onPressed: () => Navigator.pop(context, _password.text),
        ),
      ],
    );
  }
}

class _Told extends StatelessWidget {
  const _Told({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return MacSheet(
      title: 'ونه شو',
      icon: Icons.error_outline_rounded,
      iconColor: mac.red,
      width: 420,
      body: Text(message,
          style: TextStyle(fontSize: 12.5, height: 1.6, color: mac.text)),
      actions: [
        MacButton(
          label: 'ښه',
          style: MacButtonStyle.primary,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}
