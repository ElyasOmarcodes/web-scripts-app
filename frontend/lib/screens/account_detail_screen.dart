import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/security.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/identity_dialogs.dart';
import '../widgets/mac_widgets.dart';
import '../widgets/proxy_dialogs.dart';
import '../widgets/security_dialogs.dart';
import 'accounts_screen.dart' show CookieLight, cookieLook, categoryColor,
    categoryIcon;
import 'dashboard_screen.dart' show relativeTime;
import 'shell.dart';

/// One account, in full: what it is, where it goes out from, what browser it
/// appears to be, the cookies that hold its session, and the username and
/// password kept for the day the cookies stop working.
///
/// The two things that would be worth stealing — the cookies and the password —
/// start hidden and stay hidden until the app's password is typed again.
class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  AccountDetail? _detail;
  String? _error;
  bool _loading = true;

  // Revealed only after a fresh password, and forgotten as soon as the page
  // is left — nothing here is kept in memory longer than it is on screen.
  List<Map<String, dynamic>>? _cookies;
  Map<String, String>? _secrets;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final state = context.read<AppState>();
    final detail = await state.accountDetail(widget.accountId);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
      _error = detail == null ? 'اکاونټ ونه موندل شو' : null;
    });
  }

  Future<void> _revealCookies() async {
    if (_cookies != null) {
      setState(() => _cookies = null);
      return;
    }
    final proof = await askForCode(
      context,
      title: 'کوکیز ښکاره کړه',
      reason: 'کوکیز پخپله د ننوتلو کیلي ده — څوک یې ولري، ننوتلی دی.',
      icon: Icons.cookie_outlined,
    );
    if (proof == null || !mounted) return;
    final cookies = await context
        .read<AppState>()
        .revealCookies(widget.accountId, proof: proof);
    if (mounted) setState(() => _cookies = cookies);
  }

  Future<void> _revealSecrets() async {
    if (_secrets != null) {
      setState(() => _secrets = null);
      return;
    }
    final proof = await askForCode(
      context,
      title: 'کارن‌نوم او پټنوم ښکاره کړه',
      reason: 'د «${_detail?.label ?? ''}» خوندي شوي معلومات.',
      icon: Icons.key_outlined,
    );
    if (proof == null || !mounted) return;
    final secrets = await context
        .read<AppState>()
        .revealAccountSecrets(widget.accountId, proof: proof);
    if (mounted) setState(() => _secrets = secrets);
  }

  Future<void> _editSecrets() async {
    final proof = await askForCode(
      context,
      title: 'کارن‌نوم او پټنوم ثبتول',
      reason: 'دا معلومات یوازې ستاسو په کمپیوټر کې، کلپ شوي، ساتل کېږي.',
      icon: Icons.key_outlined,
    );
    if (proof == null || !mounted) return;
    final existing = _secrets ??
        await context
            .read<AppState>()
            .revealAccountSecrets(widget.accountId, proof: proof);
    if (!mounted) return;
    final edited = await editAccountSecrets(context, existing ?? const {});
    if (edited == null || !mounted) return;
    await context.read<AppState>().saveAccountSecrets(
          widget.accountId,
          proof: proof,
          username: edited['username'] ?? '',
          password: edited['password'] ?? '',
          note: edited['note'] ?? '',
        );
    if (mounted) {
      setState(() => _secrets = null);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final detail = _detail;
    if (detail == null) {
      return Center(
        child: Text(_error ?? 'ستونزه',
            style: TextStyle(fontSize: 13, color: mac.text2)),
      );
    }

    final account = state.accounts.account(detail.id);
    final color = categoryColor(mac, _categoryColor(state, detail.category));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 0),
          child: PageHeader(
            title: detail.label,
            subtitle: [
              detail.categoryName,
              if (detail.displayName.isNotEmpty) detail.displayName,
              detail.lastUsedAt == null
                  ? 'لا نه دی کارول شوی'
                  : 'وروستی کار: ${relativeTime(detail.lastUsedAt)}',
            ].join(' · '),
            actions: [
              MacButton(
                label: 'بېرته',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => state.openAccount(null),
              ),
              const SizedBox(width: 8),
              MacButton(
                label: 'کوکیز وګوره',
                icon: Icons.health_and_safety_outlined,
                style: MacButtonStyle.primary,
                onPressed: state.busy
                    ? null
                    : () => state.checkAccounts(accountIds: [detail.id]),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 18, 26, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Head(detail: detail, colour: color, state: state),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 820;
                    final cards = [
                      _RouteCard(detail: detail, account: account),
                      _IdentityCard(detail: detail, account: account),
                    ];
                    if (!wide) {
                      return Column(
                        children: [
                          cards[0],
                          const SizedBox(height: 14),
                          cards[1],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 14),
                        Expanded(child: cards[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                _SecretsCard(
                  detail: detail,
                  secrets: _secrets,
                  onReveal: _revealSecrets,
                  onEdit: _editSecrets,
                ),
                const SizedBox(height: 14),
                _CookiesCard(
                  detail: detail,
                  cookies: _cookies,
                  onReveal: _revealCookies,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _categoryColor(AppState state, String id) {
    for (final category in state.accounts.categories) {
      if (category.id == id) return category.color;
    }
    return 'blue';
  }
}

// ------------------------------------------------------------------- pieces

class _Head extends StatelessWidget {
  const _Head({
    required this.detail,
    required this.colour,
    required this.state,
  });

  final AccountDetail detail;
  final Color colour;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final checking = state.checkingAccounts.contains(detail.id);
    final look = cookieLook(mac, checking ? 'checking' : detail.cookieState);

    return _Panel(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(categoryIcon(detail.category),
                size: 22, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CookieLight(
                      state: checking ? 'checking' : detail.cookieState,
                      note: detail.cookieNote,
                      checkedAt: detail.cookieCheckedAt,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      look.label,
                      style: TextStyle(fontSize: 12.5, color: look.color),
                    ),
                    const SizedBox(width: 10),
                    MacPill('${detail.cookieCount} کوکیز'),
                  ],
                ),
                if (detail.cookieNote.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    detail.cookieNote,
                    style: TextStyle(fontSize: 11.5, color: mac.text3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.detail, required this.account});

  final AccountDetail detail;
  final Account? account;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();
    final title = switch (detail.proxyMode) {
      'random' => 'هر ځل تصادفي پروکسي',
      'fixed' when detail.proxyTitle.isNotEmpty => detail.proxyTitle,
      'fixed' => 'پروکسي ورکه ده',
      _ => 'بې پروکسي — د کمپیوټر خپله پته',
    };
    return _Panel(
      title: 'له کومې پتې وځي',
      icon: Icons.vpn_lock_outlined,
      action: account == null
          ? null
          : MacButton(
              label: 'بدلول',
              icon: Icons.tune_rounded,
              onPressed:
                  state.busy ? null : () => accountProxyFlow(context, account!),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: mac.text)),
          if (detail.proxyPlace.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(detail.proxyPlace,
                style: TextStyle(fontSize: 11.5, color: mac.text2)),
          ],
          const SizedBox(height: 9),
          Text(
            detail.proxyMode == 'none'
                ? 'دوه اکاونټه له یوې پتې، د سایټ لپاره یو کس دی.'
                : 'د ساعت او ژبې تنظیم هم له همدې هېواده اخیستل کېږي.',
            style: TextStyle(fontSize: 11, height: 1.55, color: mac.text3),
          ),
        ],
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.detail, required this.account});

  final AccountDetail detail;
  final Account? account;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();
    return _Panel(
      title: 'کومه وسیله ښکاري',
      icon: Icons.fingerprint_rounded,
      action: account == null
          ? null
          : MacButton(
              label: 'بدلول',
              icon: Icons.tune_rounded,
              onPressed: state.busy
                  ? null
                  : () => accountIdentityFlow(context, account!),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.fingerprintLabel.isEmpty
                ? 'پېژندګلوي نه ده ټاکل شوې'
                : detail.fingerprintLabel,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: mac.text),
          ),
          if (detail.fingerprintScreen.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '${ltr(detail.fingerprintScreen)} · ${detail.fingerprintGpu}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: mac.text2),
            ),
          ],
          if (detail.fingerprintUa.isNotEmpty) ...[
            const SizedBox(height: 9),
            _Mono(detail.fingerprintUa, lines: 2),
          ],
        ],
      ),
    );
  }
}

/// The account's own username and password — hidden, and gated.
class _SecretsCard extends StatelessWidget {
  const _SecretsCard({
    required this.detail,
    required this.secrets,
    required this.onReveal,
    required this.onEdit,
  });

  final AccountDetail detail;
  final Map<String, String>? secrets;
  final VoidCallback onReveal;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final saved = detail.secrets;
    final open = secrets != null;

    return _Panel(
      title: 'کارن‌نوم او پټنوم',
      icon: Icons.key_outlined,
      action: Row(
        children: [
          if (saved.any)
            MacButton(
              label: open ? 'پټ کړه' : 'ښکاره کړه',
              icon: open
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              onPressed: onReveal,
            ),
          if (saved.any) const SizedBox(width: 7),
          MacButton(
            label: saved.any ? 'بدلول' : 'ثبتول',
            icon: saved.any ? Icons.edit_outlined : Icons.add_rounded,
            style: saved.any ? MacButtonStyle.normal : MacButtonStyle.primary,
            onPressed: onEdit,
          ),
        ],
      ),
      child: !saved.any
          ? Text(
              'د دې اکاونټ لپاره هېڅ نه دي ثبت شوي. که یې ثبت کړئ، هغه ورځ چې '
              'کوکیز مړه شي، پټنوم به همدلته وي — کلپ شوی، یوازې ستاسو په '
              'کمپیوټر کې.',
              style: TextStyle(fontSize: 11.5, height: 1.6, color: mac.text3),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SecretRow(
                  label: 'کارن‌نوم',
                  value: open ? (secrets?['username'] ?? '') : null,
                  saved: saved.hasUsername,
                ),
                const SizedBox(height: 8),
                _SecretRow(
                  label: 'پټنوم',
                  value: open ? (secrets?['password'] ?? '') : null,
                  saved: saved.hasPassword,
                ),
                if (saved.hasNote) ...[
                  const SizedBox(height: 8),
                  _SecretRow(
                    label: 'یادونه',
                    value: open ? (secrets?['note'] ?? '') : null,
                    saved: true,
                  ),
                ],
                if (saved.updatedAt != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'وروستی بدلون: ${relativeTime(saved.updatedAt)}',
                    style: TextStyle(fontSize: 11, color: mac.text3),
                  ),
                ],
              ],
            ),
    );
  }
}

class _SecretRow extends StatelessWidget {
  const _SecretRow({
    required this.label,
    required this.value,
    required this.saved,
  });

  final String label;
  final String? value;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: mac.fill,
        borderRadius: BorderRadius.circular(MacRadius.row),
        border: Border.all(color: mac.hairline, width: 0.8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(label,
                style: TextStyle(fontSize: 11.5, color: mac.text3)),
          ),
          Expanded(
            child: value == null
                ? Text('••••••••',
                    style: TextStyle(
                        fontSize: 13, letterSpacing: 2, color: mac.text3))
                : Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(
                      value!.isEmpty ? '—' : value!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        color: mac.text,
                      ),
                    ),
                  ),
          ),
          if (value != null && value!.isNotEmpty)
            MacIconButton(
              icon: Icons.copy_rounded,
              tooltip: 'کاپي',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: value!)),
            ),
        ],
      ),
    );
  }
}

/// The cookies. Names always, values only after the password.
class _CookiesCard extends StatelessWidget {
  const _CookiesCard({
    required this.detail,
    required this.cookies,
    required this.onReveal,
  });

  final AccountDetail detail;
  final List<Map<String, dynamic>>? cookies;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final open = cookies != null;

    return _Panel(
      title: 'کوکیز (${detail.cookieCount})',
      icon: Icons.cookie_outlined,
      action: detail.cookieCount == 0
          ? null
          : MacButton(
              label: open ? 'پټ کړه' : 'ښکاره کړه',
              icon: open
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              style: open ? MacButtonStyle.normal : MacButtonStyle.primary,
              onPressed: onReveal,
            ),
      child: detail.cookieCount == 0
          ? Text('لا هېڅ کوکي نه ده خوندي شوې.',
              style: TextStyle(fontSize: 11.5, color: mac.text3))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (detail.cookieDomains.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final domain in detail.cookieDomains)
                          MacPill(domain),
                      ],
                    ),
                  ),
                if (!open)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: mac.orange.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(MacRadius.row),
                      border:
                          Border.all(color: mac.orange.withValues(alpha: 0.22)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 15, color: mac.orange),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'کوکیز پټ دي. دا هماغه څه دي چې ستاسو ناسته '
                            'ژوندۍ ساتي — څوک یې ولري، له پټنوم پرته ستاسو '
                            'اکاونټ ته ننوتلی شي. د لیدلو لپاره پټنوم ورکړئ.',
                            style: TextStyle(
                                fontSize: 11.5, height: 1.6, color: mac.text2),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!open) const SizedBox(height: 11),
                if (!open)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final name in detail.cookieNames) MacPill(name),
                    ],
                  )
                else
                  Column(
                    children: [
                      for (final cookie in cookies!) ...[
                        _CookieRow(cookie: cookie),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
              ],
            ),
    );
  }
}

class _CookieRow extends StatelessWidget {
  const _CookieRow({required this.cookie});

  final Map<String, dynamic> cookie;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final value = '${cookie['value'] ?? ''}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: mac.fill,
        borderRadius: BorderRadius.circular(MacRadius.row),
        border: Border.all(color: mac.hairline, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '${cookie['name'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: mac.text,
                ),
              ),
            ),
          ),
          Expanded(child: _Mono(value, lines: 2, selectable: true)),
          MacIconButton(
            icon: Icons.copy_rounded,
            tooltip: 'کاپي',
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
          ),
        ],
      ),
    );
  }
}

class _Mono extends StatelessWidget {
  const _Mono(this.text, {this.lines = 1, this.selectable = false});

  final String text;
  final int lines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final style = TextStyle(
      fontSize: 11.5,
      fontFamily: 'monospace',
      height: 1.5,
      color: mac.text2,
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: selectable
          ? SelectableText(text, maxLines: lines, style: style)
          : Text(text, maxLines: lines, overflow: TextOverflow.ellipsis,
              style: style),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.title, this.icon, this.action});

  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mac.window,
        borderRadius: BorderRadius.circular(MacRadius.card),
        border: Border.all(color: mac.hairline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: mac.text3),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: mac.text,
                    ),
                  ),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 13),
          ],
          child,
        ],
      ),
    );
  }
}
