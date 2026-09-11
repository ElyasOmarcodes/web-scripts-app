import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/proxy.dart';
import '../screens/proxies_screen.dart' show ProxyLight, proxyLook;
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import 'dialogs.dart';
import 'mac_widgets.dart';

/// Paste a list from the seller. Every common shape is understood, so the
/// user never has to reformat what they were given.
Future<void> importProxiesFlow(BuildContext context) async {
  final state = context.read<AppState>();
  await showMacSheet<void>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const _ImportSheet(),
    ),
  );
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet();

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final _text = TextEditingController();
  final _label = TextEditingController();
  Map<String, dynamic>? _result;
  bool _working = false;

  @override
  void dispose() {
    _text.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _working = true);
    final result = await context
        .read<AppState>()
        .importProxies(text, label: _label.text.trim());
    if (mounted) {
      setState(() {
        _working = false;
        _result = result;
        if (result != null) _text.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final result = _result;

    return MacSheet(
      title: 'پروکسي زیاتول',
      subtitle: 'لیست دلته پېسټ کړئ — هره کرښه یوه پروکسي',
      icon: Icons.vpn_lock_outlined,
      width: 620,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetLabel('لیست'),
          Container(
            height: 170,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: mac.window,
              borderRadius: BorderRadius.circular(MacRadius.control),
              border: Border.all(color: mac.hairline, width: 0.8),
            ),
            child: Directionality(
              // Addresses are latin text, whatever the page direction is.
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _text,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                autofocus: true,
                style: TextStyle(
                  fontSize: 12.5,
                  color: mac.text,
                  fontFamilyFallback: const ['Menlo', 'monospace'],
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: '203.0.113.11:6754:user:pass\n'
                      '203.0.113.24:6014:user:pass',
                  hintStyle: TextStyle(fontSize: 12.5, color: mac.text3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'پېژندل شوې بڼې: host:port · host:port:user:pass · '
            'user:pass@host:port · http(s)/socks5://…',
            style: TextStyle(fontSize: 11.5, color: mac.text2, height: 1.5),
          ),
          const SizedBox(height: 13),
          const SheetLabel('نوم (اختیاري)'),
          MacField(controller: _label, hint: 'لکه: Webshare'),
          if (result != null) ...[
            const SizedBox(height: 14),
            _ImportReport(result: result),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
            decoration: BoxDecoration(
              color: mac.fill,
              borderRadius: BorderRadius.circular(MacRadius.card),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 15, color: mac.text2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'د پروکسۍ پټنومونه ستاسو په کمپیوټر کې خوندي کېږي '
                    '(یوازې د مالک د لوستلو اجازه) او هېڅکله بهر نه لېږل کېږي.',
                    style: TextStyle(
                        fontSize: 11.5, color: mac.text2, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        MacButton(
          label: _working ? 'زیاتېږي…' : 'زیات یې کړه',
          icon: Icons.add_rounded,
          style: MacButtonStyle.primary,
          large: true,
          onPressed: _working ? null : _import,
        ),
        const SizedBox(width: 10),
        MacButton(
          label: 'بندول',
          large: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _ImportReport extends StatelessWidget {
  const _ImportReport({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final added = (result['added'] as List<dynamic>? ?? []).length;
    final skipped = (result['skipped'] as num? ?? 0).toInt();
    final rejected =
        (result['rejected'] as List<dynamic>? ?? []).map((e) => '$e').toList();
    final good = added > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: (good ? mac.green : mac.orange).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(MacRadius.card),
        border: Border.all(
          color: (good ? mac.green : mac.orange).withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(good ? Icons.check_circle : Icons.info_outline,
                  size: 15, color: good ? mac.green : mac.orange),
              const SizedBox(width: 8),
              Text(
                '$added نوې زیاتې شوې'
                '${skipped > 0 ? ' · $skipped مخکې شته وې' : ''}'
                '${rejected.isEmpty ? '' : ' · ${rejected.length} ونه پېژندل شوې'}',
                style: TextStyle(fontSize: 12.5, color: mac.text),
              ),
            ],
          ),
          if (rejected.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final line in rejected.take(4))
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  line,
                  style: TextStyle(fontSize: 11.5, color: mac.text3),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Which way out this account uses. Opened from the account's own card.
Future<void> accountProxyFlow(BuildContext context, Account account) async {
  final state = context.read<AppState>();
  final picked = await showMacSheet<_ProxyChoice>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: _AccountProxySheet(account: account),
    ),
  );
  if (picked == null) return;
  await state.assignProxy(account.id,
      proxyId: picked.proxyId, mode: picked.mode);
}

class _ProxyChoice {
  const _ProxyChoice(this.proxyId, this.mode);

  final String proxyId;
  final String mode;
}

class _AccountProxySheet extends StatefulWidget {
  const _AccountProxySheet({required this.account});

  final Account account;

  @override
  State<_AccountProxySheet> createState() => _AccountProxySheetState();
}

class _AccountProxySheetState extends State<_AccountProxySheet> {
  late String _mode;
  late String _proxyId;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _mode = widget.account.proxyMode;
    _proxyId = widget.account.proxyId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final book = context.watch<AppState>().proxies;
    final needle = _search.text.trim().toLowerCase();
    final options = book.proxies
        .where((p) =>
            needle.isEmpty ||
            p.address.toLowerCase().contains(needle) ||
            p.place.toLowerCase().contains(needle) ||
            p.label.toLowerCase().contains(needle))
        .toList();

    return MacSheet(
      title: 'د دې اکاونټ پروکسي',
      subtitle: widget.account.label,
      icon: Icons.vpn_lock_outlined,
      width: 600,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          MacSegmented<String>(
            value: _mode,
            items: const {
              'none': 'بې پروکسي',
              'fixed': 'ټاکلې پروکسي',
              'random': 'هر ځل تصادفي',
            },
            onChanged: (value) => setState(() => _mode = value),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
            decoration: BoxDecoration(
              color: _mode == 'random'
                  ? mac.orange.withValues(alpha: 0.10)
                  : mac.fill,
              borderRadius: BorderRadius.circular(MacRadius.card),
            ),
            child: Row(
              children: [
                Icon(
                  _mode == 'random'
                      ? Icons.warning_amber_rounded
                      : Icons.info_outline_rounded,
                  size: 15,
                  color: _mode == 'random' ? mac.orange : mac.text2,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    switch (_mode) {
                      'none' =>
                        'دا اکاونټ به ستاسو د کمپیوټر له خپلې پتې ووځي.',
                      'random' =>
                        'هر ځل به بله پروکسي وکاروي. یاد ولرئ: هغه اکاونټ چې '
                            'ای‌پي یې هره ورځ بدلېږي، سایټ ته ډېر عجیب ښکاري '
                            'له هغه چې تل له یوې پتې راځي — نو ټاکلې پروکسي '
                            'خوندي ده.',
                      _ =>
                        'تل به له همدې یوې پتې ووځي — دا تر ټولو خوندي بڼه ده.',
                    },
                    style: TextStyle(
                        fontSize: 11.5, color: mac.text2, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          if (_mode == 'fixed') ...[
            const SizedBox(height: 13),
            MacField(
              controller: _search,
              hint: 'پته، نوم یا هېواد…',
              prefix: Icon(Icons.search_rounded, size: 14, color: mac.text3),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 230,
              child: options.isEmpty
                  ? Center(
                      child: Text(
                        book.total == 0
                            ? 'لا هېڅ پروکسي نشته — د «پروکسي» پاڼې څخه یې زیاتې کړئ.'
                            : 'هېڅ پروکسي ونه موندل شوه',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: mac.text2),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: mac.window,
                        borderRadius: BorderRadius.circular(MacRadius.card),
                        border: Border.all(color: mac.hairline, width: 0.8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(6),
                        itemCount: options.length,
                        itemBuilder: (context, index) => _ProxyOption(
                          proxy: options[index],
                          selected: _proxyId == options[index].id,
                          onTap: () =>
                              setState(() => _proxyId = options[index].id),
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
      actions: [
        MacButton(
          label: 'خوندي کړه',
          icon: Icons.check_rounded,
          style: MacButtonStyle.primary,
          large: true,
          onPressed: _mode == 'fixed' && _proxyId.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    _ProxyChoice(_mode == 'fixed' ? _proxyId : '', _mode),
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

class _ProxyOption extends StatelessWidget {
  const _ProxyOption({
    required this.proxy,
    required this.selected,
    required this.onTap,
  });

  final WebProxy proxy;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? mac.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(MacRadius.row),
            border: Border.all(
              color: selected ? mac.accent : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              ProxyLight(state: proxy.status, note: proxy.note),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        proxy.exitIp.isEmpty ? proxy.address : proxy.exitIp,
                        style: TextStyle(fontSize: 12.5, color: mac.text),
                      ),
                    ),
                    Text(
                      [
                        if (proxy.place.isNotEmpty) proxy.place,
                        if (proxy.usedBy > 0)
                          '${proxy.usedBy} اکاونټه یې کاروي',
                        if (proxy.usedBy == 0) 'ازاده',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11, color: mac.text3),
                    ),
                  ],
                ),
              ),
              if (proxy.latencyMs != null)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '${proxy.latencyMs} ms',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: proxyLook(mac, proxy.status).color),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
