import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/security.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/mac_widgets.dart';

/// The first thing the app shows, and the only thing it shows while it is shut.
///
/// On a machine that has never run WebScripts it asks for a *new* password;
/// afterwards it asks for that one. The password is the app's own — deliberately
/// not the computer's, so that the two are not the same secret — with the
/// computer's password and the fingerprint offered alongside it as extra doors
/// for anyone who wants them.
class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();

    return Container(
      color: mac.content,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          child: SizedBox(
            width: 430,
            child: state.security.configured
                ? const _UnlockCard()
                : const _SetupCard(),
          ),
        ),
      ),
    );
  }
}

/// The badge at the top of both cards.
class _Crest extends StatelessWidget {
  const _Crest({required this.title, required this.subtitle, required this.icon});

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [mac.accent, mac.accent.withValues(alpha: 0.72)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: mac.accent.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon, size: 27, color: Colors.white),
        ),
        const SizedBox(height: 15),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: mac.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, height: 1.6, color: mac.text2),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
      decoration: BoxDecoration(
        color: mac.window,
        borderRadius: BorderRadius.circular(MacRadius.sheet),
        border: Border.all(color: mac.hairline, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

// --------------------------------------------------------------- first run

class _SetupCard extends StatefulWidget {
  const _SetupCard();

  @override
  State<_SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends State<_SetupCard> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  final _windows = TextEditingController();
  bool _useWindows = false;
  bool _useBiometric = false;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    _windows.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final password = _password.text;
    if (password.length < state.security.minLength) {
      setState(() => _error =
          'پټنوم باید لږ تر لږه ${state.security.minLength} تورې ولري.');
      return;
    }
    if (password != _again.text) {
      setState(() => _error = 'دواړه پټنومونه یو شان نه دي.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final failure = await state.setupSecurity(
      password: password,
      useWindowsPassword: _useWindows,
      windowsPassword: _windows.text,
      useBiometric: _useBiometric,
    );
    if (mounted) {
      setState(() {
        _working = false;
        _error = failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final security = context.watch<AppState>().security;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Crest(
            icon: Icons.lock_outline_rounded,
            title: 'خپل پټنوم وټاکئ',
            subtitle: 'دا پروګرام ستاسو د اکاونټونو کوکیز، پروکسي پټنومونه او '
                'د اکاونټونو خپل پټنومونه ساتي. له دې وروسته هر څه د همدې '
                'پټنوم لاندې کلپ کېږي.',
          ),
          const SizedBox(height: 20),
          const _Label('نوی پټنوم'),
          MacField(
            controller: _password,
            obscure: true,
            autofocus: true,
            hint: 'لږ تر لږه ${security.minLength} تورې',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _Strength(password: _password.text, minLength: security.minLength),
          const SizedBox(height: 13),
          const _Label('بیا یې ولیکئ'),
          MacField(
            controller: _again,
            obscure: true,
            onSubmitted: (_) => _save(),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          Divider(height: 1, thickness: 0.8, color: mac.hairline),
          const SizedBox(height: 14),
          Text(
            'نور لارې (اختیاري)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: mac.text2,
            ),
          ),
          const SizedBox(height: 10),
          _WindowsOption(
            security: security,
            value: _useWindows,
            controller: _windows,
            onChanged: (value) => setState(() => _useWindows = value),
          ),
          const SizedBox(height: 9),
          _BiometricOption(
            security: security,
            value: _useBiometric,
            onChanged: (value) => setState(() => _useBiometric = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _Problem(_error!),
          ],
          const SizedBox(height: 18),
          MacButton(
            label: _working ? 'ثبتېږي…' : 'پټنوم وټاکه او پیل وکړه',
            icon: Icons.check_rounded,
            style: MacButtonStyle.primary,
            expand: true,
            onPressed: _working ? null : _save,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: mac.text3),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'دا پټنوم هېڅ ځای ته نه لېږل کېږي او په فایل کې هم نه لیکل '
                  'کېږي — یوازې ستاسو په کمپیوټر کې د کلي د پرانیستلو لپاره '
                  'کارېږي. که یې هېر کړئ، خوندي شوي معلومات بیرته نه راځي.',
                  style: TextStyle(fontSize: 11, height: 1.6, color: mac.text3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- unlocking

class _UnlockCard extends StatefulWidget {
  const _UnlockCard();

  @override
  State<_UnlockCard> createState() => _UnlockCardState();
}

class _UnlockCardState extends State<_UnlockCard> {
  final _password = TextEditingController();
  String _method = 'password';
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _open({String? method}) async {
    final how = method ?? _method;
    setState(() {
      _working = true;
      _error = null;
      _method = how;
    });
    final failure = await context
        .read<AppState>()
        .unlock(password: how == 'biometric' ? '' : _password.text, method: how);
    if (mounted) {
      setState(() {
        _working = false;
        _error = failure;
        if (failure != null) _password.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final security = context.watch<AppState>().security;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Crest(
            icon: Icons.lock_rounded,
            title: 'ښه راغلاست',
            subtitle: 'د دوام لپاره خپل پټنوم ولیکئ.',
          ),
          const SizedBox(height: 20),
          MacField(
            controller: _password,
            obscure: true,
            autofocus: true,
            hint: _method == 'windows'
                ? 'د ویندوز پټنوم (${security.windowsUser})'
                : 'پټنوم',
            prefix: Icon(
              _method == 'windows'
                  ? Icons.desktop_windows_outlined
                  : Icons.key_outlined,
              size: 14,
              color: mac.text3,
            ),
            onSubmitted: (_) => _open(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 13),
            _Problem(_error!),
          ],
          const SizedBox(height: 16),
          MacButton(
            label: _working ? 'کتل کېږي…' : 'پرانیستل',
            icon: Icons.lock_open_rounded,
            style: MacButtonStyle.primary,
            expand: true,
            onPressed: _working ? null : () => _open(method: _method),
          ),
          if (security.windowsEnabled || security.biometricEnabled) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Divider(thickness: 0.8, color: mac.hairline)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('یا',
                      style: TextStyle(fontSize: 11.5, color: mac.text3)),
                ),
                Expanded(child: Divider(thickness: 0.8, color: mac.hairline)),
              ],
            ),
            const SizedBox(height: 12),
            if (security.biometricEnabled)
              MacButton(
                label: 'د ګوتې نښه',
                icon: Icons.fingerprint_rounded,
                expand: true,
                onPressed: _working ? null : () => _open(method: 'biometric'),
              ),
            if (security.biometricEnabled && security.windowsEnabled)
              const SizedBox(height: 8),
            if (security.windowsEnabled)
              MacButton(
                label: _method == 'windows'
                    ? 'د پروګرام خپل پټنوم وکاروه'
                    : 'د ویندوز پټنوم وکاروه',
                icon: Icons.desktop_windows_outlined,
                expand: true,
                onPressed: _working
                    ? null
                    : () => setState(() {
                          _method =
                              _method == 'windows' ? 'password' : 'windows';
                          _error = null;
                        }),
              ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ pieces

class _Label extends StatelessWidget {
  const _Label(this.text);

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

/// How hard this password would be to guess — shown while it is being typed,
/// which is the only moment the answer can still change anything.
class _Strength extends StatelessWidget {
  const _Strength({required this.password, required this.minLength});

  final String password;
  final int minLength;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    if (password.isEmpty) {
      return Text(
        'یو څه چې یوازې تاسو یې پېژنئ — نه د زېږېدو نېټه، نه د اکاونټ نوم.',
        style: TextStyle(fontSize: 11, color: mac.text3),
      );
    }
    final score = _score(password);
    final (label, colour) = switch (score) {
      <= 1 => ('کمزوری', mac.red),
      2 => ('منځنی', mac.orange),
      3 => ('ښه', mac.green),
      _ => ('ډېر ښه', mac.green),
    };
    return Row(
      children: [
        for (var index = 0; index < 4; index++) ...[
          Expanded(
            child: Container(
              height: 3.5,
              decoration: BoxDecoration(
                color: index < score ? colour : mac.fill2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (index < 3) const SizedBox(width: 4),
        ],
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 11, color: colour)),
      ],
    );
  }

  int _score(String value) {
    var score = 0;
    if (value.length >= minLength) score++;
    if (value.length >= 12) score++;
    if (RegExp(r'[0-9]').hasMatch(value) &&
        RegExp(r'[^0-9a-zA-Z]').hasMatch(value)) {
      score++;
    }
    if (RegExp(r'[a-z]').hasMatch(value) && RegExp(r'[A-Z]').hasMatch(value)) {
      score++;
    }
    return score.clamp(0, 4);
  }
}

/// "Use my Windows password as well."
class _WindowsOption extends StatelessWidget {
  const _WindowsOption({
    required this.security,
    required this.value,
    required this.onChanged,
    this.controller,
  });

  final SecurityState security;
  final bool value;
  final ValueChanged<bool> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final possible = security.windowsAvailable;
    return _Option(
      icon: Icons.desktop_windows_outlined,
      title: 'د کمپیوټر پټنوم هم ومنه',
      note: possible
          ? 'د ویندوز د «${security.windowsUser}» پټنوم به پروګرام هم '
              'پرانیزي. پورتنی پټنوم په خپل ځای پاتې کېږي — که کله د ویندوز '
              'پټنوم بدل کړئ، له خپلو اکاونټونو بهر پاتې نه شئ.'
          : 'دا امکان یوازې په ویندوز کې شته.',
      enabled: possible,
      value: value,
      onChanged: onChanged,
      child: value && controller != null
          ? Padding(
              padding: const EdgeInsets.only(top: 9),
              child: MacField(
                controller: controller,
                obscure: true,
                hint: 'د ویندوز پټنوم — ویندوز پخپله یې کوي',
                prefix: Icon(Icons.badge_outlined, size: 14, color: mac.text3),
              ),
            )
          : null,
    );
  }
}

/// "Use my fingerprint." Shown even where it cannot work, with the reason —
/// a greyed row that explains itself beats an option that silently vanished.
class _BiometricOption extends StatelessWidget {
  const _BiometricOption({
    required this.security,
    required this.value,
    required this.onChanged,
  });

  final SecurityState security;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ready = security.biometricReady;
    return _Option(
      icon: Icons.fingerprint_rounded,
      title: 'د ګوتې نښه ومنه',
      note: ready
          ? 'ویندوز هیلو چمتو ده — یوه ګوته بس ده.'
          : security.biometricMessage,
      enabled: ready,
      value: value && ready,
      onChanged: onChanged,
      trailing: security.biometricNeedsEnrolment
          ? MacButton(
              label: 'ګوته ثبت کړه',
              icon: Icons.open_in_new_rounded,
              onPressed: () =>
                  context.read<AppState>().openFingerprintEnrolment(),
            )
          : null,
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.note,
    required this.enabled,
    required this.value,
    required this.onChanged,
    this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String note;
  final bool enabled;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final colour = enabled ? mac.text : mac.text3;
    return Opacity(
      opacity: enabled ? 1 : 0.62,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
        decoration: BoxDecoration(
          color: value ? mac.accent.withValues(alpha: 0.07) : mac.fill,
          borderRadius: BorderRadius.circular(MacRadius.row),
          border: Border.all(
            color: value ? mac.accent.withValues(alpha: 0.35) : mac.hairline,
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: enabled ? mac.accent : mac.text3),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: colour,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        note,
                        style: TextStyle(
                            fontSize: 11, height: 1.55, color: mac.text3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
                MacSwitch(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                ),
              ],
            ),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: mac.red.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(MacRadius.row),
        border: Border.all(color: mac.red.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: mac.red),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11.5, height: 1.5, color: mac.text),
            ),
          ),
        ],
      ),
    );
  }
}
