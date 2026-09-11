import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/proxy.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/mac_widgets.dart';
import '../widgets/proxy_dialogs.dart';

import 'shell.dart';

enum ProxyFilter { all, alive, dead, unknown, free }

/// Where the accounts go out from.
class ProxiesScreen extends StatefulWidget {
  const ProxiesScreen({super.key});

  @override
  State<ProxiesScreen> createState() => _ProxiesScreenState();
}

class _ProxiesScreenState extends State<ProxiesScreen> {
  ProxyFilter _filter = ProxyFilter.all;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final book = state.proxies;
    final rows = _apply(book.proxies);

    return PageBody(
      header: PageHeader(
        title: 'پروکسي',
        subtitle: book.total == 0
            ? 'هر اکاونټ خپله پته — چې ټول له یوه ای‌پي څخه نه ښکاري'
            : '${book.total} پروکسي · ${book.alive} ژوندۍ · '
                '${book.overview['assigned'] ?? 0} ټاکل شوې',
        actions: [
          SizedBox(
            width: 170,
            child: MacField(
              controller: _search,
              hint: 'پته یا هېواد…',
              prefix: Icon(Icons.search_rounded,
                  size: 14, color: MacPalette.of(context).text3),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          MacButton(
            label: state.session == SessionState.checking
                ? 'کتل روان دي…'
                : 'ټولې وګوره',
            icon: Icons.network_check_rounded,
            onPressed: state.busy || book.total == 0
                ? null
                : () => state.checkProxies(),
          ),
          const SizedBox(width: 8),
          MacButton(
            label: 'پروکسي زیاتول',
            icon: Icons.add_rounded,
            style: MacButtonStyle.primary,
            onPressed: state.busy ? null : () => importProxiesFlow(context),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (book.total > 0) ...[
            _Distribute(state: state),
            const SizedBox(height: 12),
            _FilterRow(
              value: _filter,
              counts: _counts(book),
              onChanged: (value) => setState(() => _filter = value),
            ),
            const SizedBox(height: 12),
          ],
          if (rows.isEmpty)
            _Empty(hasAny: book.total > 0)
          else
            MacCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _HeaderRow(),
                  for (final proxy in rows)
                    ProxyRow(proxy: proxy, state: state),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Map<ProxyFilter, int> _counts(ProxyBook book) => {
        ProxyFilter.all: book.proxies.length,
        ProxyFilter.alive: book.proxies.where((p) => p.alive).length,
        ProxyFilter.dead: book.proxies.where((p) => p.dead).length,
        ProxyFilter.unknown:
            book.proxies.where((p) => !p.alive && !p.dead).length,
        ProxyFilter.free: book.proxies.where((p) => p.usedBy == 0).length,
      };

  List<WebProxy> _apply(List<WebProxy> proxies) {
    final needle = _search.text.trim().toLowerCase();
    return proxies.where((proxy) {
      final passes = switch (_filter) {
        ProxyFilter.all => true,
        ProxyFilter.alive => proxy.alive,
        ProxyFilter.dead => proxy.dead,
        ProxyFilter.unknown => !proxy.alive && !proxy.dead,
        ProxyFilter.free => proxy.usedBy == 0,
      };
      if (!passes) return false;
      if (needle.isEmpty) return true;
      return proxy.address.toLowerCase().contains(needle) ||
          proxy.label.toLowerCase().contains(needle) ||
          proxy.place.toLowerCase().contains(needle) ||
          proxy.exitIp.contains(needle);
    }).toList();
  }
}

/// The one action that ties the two pages together.
class _Distribute extends StatelessWidget {
  const _Distribute({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final accounts = state.accounts.accounts.length;
    final withProxy = state.accounts.accounts.where((a) => a.usesProxy).length;
    final usable = state.proxies.usable.length;
    final short = accounts > usable;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: mac.accentSoft,
        borderRadius: BorderRadius.circular(MacRadius.card),
        border:
            Border.all(color: mac.accent.withValues(alpha: 0.22), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(Icons.hub_outlined, size: 17, color: mac.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$withProxy له $accounts اکاونټونو خپله پروکسي لري',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: mac.text),
                ),
                const SizedBox(height: 2),
                Text(
                  short
                      ? '$usable فعالې پروکسۍ شته — ځینې اکاونټونه به یوه شریکه کړي.'
                      : 'هر اکاونټ ته یوه جلا پروکسي ورکول کېږي، او همغه یې پاتې کېږي.',
                  style:
                      TextStyle(fontSize: 11.5, color: mac.text2, height: 1.5),
                ),
              ],
            ),
          ),
          MacButton(
            label: 'اکاونټونو ته ووېشه',
            icon: Icons.shuffle_rounded,
            onPressed: state.busy || usable == 0 || accounts == 0
                ? null
                : () => _distribute(context),
          ),
        ],
      ),
    );
  }

  Future<void> _distribute(BuildContext context) async {
    final accounts = state.accounts.accounts.length;
    final usable = state.proxies.usable.length;
    final ok = await confirmSheet(
      context,
      title: 'پروکسۍ ووېشل شي؟',
      message: accounts > usable
          ? '$accounts اکاونټونه او $usable فعالې پروکسۍ — ځینې به یوه '
              'پروکسي شریکه کړي. پخوانۍ ټاکنې به بدلې شي.'
          : 'هر یو له $accounts اکاونټونو به خپله جلا پروکسي واخلي. '
              'پخوانۍ ټاکنې به بدلې شي.',
      confirmLabel: 'ووېشه',
    );
    if (!ok || !context.mounted) return;
    final result = await context.read<AppState>().distributeProxies();
    if (result != null && context.mounted) {
      final shared = (result['shared'] as num? ?? 0).toInt();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shared == 0
                ? '${result['assigned']} اکاونټونو ته یو یو پروکسي ورکړل شو.'
                : '${result['assigned']} اکاونټونه ووېشل شول — $shared یې پروکسي شریکوي.',
            style: const TextStyle(fontSize: 13),
          ),
          behavior: SnackBarBehavior.floating,
          width: 520,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.value,
    required this.counts,
    required this.onChanged,
  });

  final ProxyFilter value;
  final Map<ProxyFilter, int> counts;
  final ValueChanged<ProxyFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    const labels = {
      ProxyFilter.all: 'ټولې',
      ProxyFilter.alive: 'ژوندۍ',
      ProxyFilter.dead: 'مړې',
      ProxyFilter.unknown: 'نامعلومې',
      ProxyFilter.free: 'ازادې',
    };
    Color colour(ProxyFilter filter) => switch (filter) {
          ProxyFilter.alive => mac.green,
          ProxyFilter.dead => mac.red,
          ProxyFilter.unknown => mac.text3,
          ProxyFilter.free => mac.accent,
          ProxyFilter.all => mac.text2,
        };

    return Row(
      children: [
        for (final filter in ProxyFilter.values) ...[
          StatusChip(
            label: labels[filter]!,
            count: counts[filter] ?? 0,
            color: colour(filter),
            selected: value == filter,
            onTap: () => onChanged(filter),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// Column widths live here and in _ProxyRowState, in one place each.
const _colAddress = 5;
const _colExitIp = 4;
const _colPlace = 4;
const _colPing = 2;
const _colUsers = 4;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final style = TextStyle(
        fontSize: 11.5, fontWeight: FontWeight.w600, color: mac.text3);
    Widget cell(int flex, String label) => Expanded(
          flex: flex,
          child: Padding(
            // Gutter: without it the columns read as one run-on string.
            padding: const EdgeInsetsDirectional.only(start: 12),
            child: Text(label, style: style, overflow: TextOverflow.ellipsis),
          ),
        );

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: mac.hairline, width: 0.8)),
      ),
      child: Row(
        children: [
          cell(_colAddress, 'پته'),
          cell(_colExitIp, 'وتنځی ای‌پي'),
          cell(_colPlace, 'ځای'),
          cell(_colPing, 'ځواب'),
          cell(_colUsers, 'اکاونټونه'),
          // Room for the row's buttons, which the header does not have.
          const SizedBox(width: 104),
        ],
      ),
    );
  }
}

/// One column of the table, with the gutter that keeps it off its neighbour.
class _Cell extends StatelessWidget {
  const _Cell({required this.flex, required this.child});

  final int flex;
  final Widget child;

  @override
  Widget build(BuildContext context) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 12),
          child: child,
        ),
      );
}

class ProxyRow extends StatefulWidget {
  const ProxyRow({super.key, required this.proxy, required this.state});

  final WebProxy proxy;
  final AppState state;

  @override
  State<ProxyRow> createState() => _ProxyRowState();
}

class _ProxyRowState extends State<ProxyRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final proxy = widget.proxy;
    final checking = widget.state.checkingProxies.contains(proxy.id);
    final status = checking ? 'checking' : proxy.status;
    final look = proxyLook(mac, status);
    final users = widget.state.accounts.accounts
        .where((a) => a.proxyId == proxy.id && a.usesProxy)
        .toList();

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _hover ? mac.fill : Colors.transparent,
          border: Border(bottom: BorderSide(color: mac.hairline, width: 0.5)),
        ),
        child: Opacity(
          opacity: proxy.enabled ? 1 : 0.5,
          child: Row(
            children: [
              Expanded(
                flex: _colAddress,
                child: Row(
                  children: [
                    ProxyLight(state: status, note: proxy.note),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              proxy.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: mac.text),
                            ),
                          ),
                          Text(
                            [
                              proxy.scheme,
                              if (proxy.needsAuth) 'پټنوم',
                              if (!proxy.enabled) 'بنده',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: mac.text3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _Cell(
                flex: _colExitIp,
                child: proxy.exitIp.isEmpty
                    ? Text('—',
                        style: TextStyle(fontSize: 12, color: mac.text3))
                    : Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          proxy.exitIp,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: mac.text2),
                        ),
                      ),
              ),
              _Cell(
                flex: _colPlace,
                child: Text(
                  proxy.place.isEmpty ? '—' : proxy.place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: mac.text2),
                ),
              ),
              _Cell(
                flex: _colPing,
                child: proxy.latencyMs == null
                    ? Text('—',
                        style: TextStyle(fontSize: 12, color: mac.text3))
                    : Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          '${proxy.latencyMs} ms',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            // Slow but working: worth flagging, not failing.
                            color: proxy.latencyMs! > 1500
                                ? mac.orange
                                : look.color,
                          ),
                        ),
                      ),
              ),
              _Cell(
                flex: _colUsers,
                child: users.isEmpty
                    ? Text('ازاده',
                        style: TextStyle(fontSize: 12, color: mac.text3))
                    : Text(
                        users.map((a) => a.label).join('، '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: mac.text2),
                      ),
              ),
              SizedBox(
                width: 104,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: _hover ? 1 : 0.35,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      MacIconButton(
                        icon: Icons.network_check_rounded,
                        tooltip: 'دا پروکسي وګوره',
                        onPressed: widget.state.busy
                            ? null
                            : () =>
                                widget.state.checkProxies(proxyIds: [proxy.id]),
                      ),
                      MacIconButton(
                        icon: proxy.enabled
                            ? Icons.pause_circle_outline_rounded
                            : Icons.play_circle_outline_rounded,
                        tooltip: proxy.enabled ? 'بندول' : 'فعالول',
                        onPressed: widget.state.busy
                            ? null
                            : () => widget.state.updateProxy(
                                proxy.id, {'enabled': !proxy.enabled}),
                      ),
                      MacIconButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'ړنګول',
                        onPressed:
                            widget.state.busy ? null : () => _delete(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final users = widget.proxy.usedBy;
    final ok = await confirmSheet(
      context,
      title: 'دا پروکسي ړنګه شي؟',
      message: users == 0
          ? '«${widget.proxy.title}» ړنګېږي.'
          : '«${widget.proxy.title}» ړنګېږي — $users اکاونټه یې کاروي او '
              'بیا به د کمپیوټر له خپلې پتې ووځي.',
      confirmLabel: 'ړنګه یې کړه',
    );
    if (ok && context.mounted) {
      await context.read<AppState>().deleteProxy(widget.proxy.id);
    }
  }
}

/// Colour and words for a proxy's state.
({Color color, String label}) proxyLook(MacPalette mac, String status) {
  switch (status) {
    case 'alive':
      return (color: mac.green, label: 'ژوندۍ ده');
    case 'dead':
      return (color: mac.red, label: 'مړه ده');
    case 'checking':
      return (color: mac.orange, label: 'کتل کېږي…');
    default:
      return (color: mac.text3, label: 'لا نه ده کتل شوې');
  }
}

class ProxyLight extends StatelessWidget {
  const ProxyLight({super.key, required this.state, this.note = ''});

  final String state;
  final String note;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final look = proxyLook(mac, state);
    return Tooltip(
      message: note.isEmpty ? look.label : '${look.label}\n$note',
      waitDuration: const Duration(milliseconds: 400),
      child: state == 'checking'
          ? SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                  strokeWidth: 1.6, color: look.color),
            )
          : Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: look.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: look.color.withValues(alpha: 0.45), blurRadius: 4),
                ],
              ),
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.hasAny});

  final bool hasAny;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return MacCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 24),
        child: Column(
          children: [
            Icon(Icons.vpn_lock_outlined, size: 30, color: mac.text3),
            const SizedBox(height: 12),
            Text(
              hasAny ? 'په دې فلټر کې هېڅ پروکسي نشته' : 'لا هېڅ پروکسي نشته',
              style: TextStyle(fontSize: 14, color: mac.text),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 520,
              child: Text(
                'که ستاسو درې اکاونټونه له یوه ای‌پي څخه وصل شي، سایټ یې یو کس '
                'ګڼي. هر اکاونټ ته خپله پروکسي ورکړئ — لیست له خرڅوونکي (لکه '
                'Webshare) واخلئ او دلته یې ټول یو ځای پېسټ کړئ.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: mac.text2, height: 1.6),
              ),
            ),
            const SizedBox(height: 16),
            MacButton(
              label: 'پروکسي زیاتول',
              icon: Icons.add_rounded,
              style: MacButtonStyle.primary,
              large: true,
              onPressed: () => importProxiesFlow(context),
            ),
          ],
        ),
      ),
    );
  }
}
