import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/fingerprint.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import 'dialogs.dart';
import 'mac_widgets.dart';

/// The browser identity an account wears, and the whole catalogue behind it.
///
/// Normally nothing is chosen here: every account is given its own identity
/// the moment it is created. The sheet exists for the one case that matters —
/// two accounts that ended up on the same device, which is the situation this
/// whole feature is meant to prevent.
Future<void> accountIdentityFlow(BuildContext context, Account account) async {
  final state = context.read<AppState>();
  final picked = await showMacSheet<String>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: _IdentitySheet(account: account),
    ),
  );
  if (picked == null || picked == account.fingerprintId) return;
  await state.assignIdentity(account.id, picked);
}

class _IdentitySheet extends StatefulWidget {
  const _IdentitySheet({required this.account});

  final Account account;

  @override
  State<_IdentitySheet> createState() => _IdentitySheetState();
}

class _IdentitySheetState extends State<_IdentitySheet> {
  late String _chosen = widget.account.fingerprintId;
  String _tier = 'safe';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final book = context.watch<AppState>().identities;
    final needle = _search.text.trim().toLowerCase();

    final shown = book.profiles.where((profile) {
      if (profile.tier != _tier) return false;
      if (needle.isEmpty) return true;
      return profile.label.toLowerCase().contains(needle) ||
          profile.ua.toLowerCase().contains(needle) ||
          profile.gpu.toLowerCase().contains(needle);
    }).toList()
      // The account's own identity first, then the ones nobody uses: those
      // are the two things anyone opening this sheet is looking for.
      ..sort((a, b) {
        if (a.id == widget.account.fingerprintId) return -1;
        if (b.id == widget.account.fingerprintId) return 1;
        return a.usedBy == b.usedBy
            ? b.version.compareTo(a.version)
            : a.usedBy.compareTo(b.usedBy);
      });

    final tier = book.tiers.where((t) => t.id == _tier).firstOrNull;

    return MacSheet(
      title: 'د براوزر پېژندګلوي',
      subtitle: '«${widget.account.label}» کوم وسیله ښکاري — '
          '${book.total} چاپېریالونه شته',
      icon: Icons.fingerprint_rounded,
      width: 640,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _WhyBox(),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final option in book.tiers) ...[
                StatusChip(
                  label: option.label,
                  color: switch (option.id) {
                    'safe' => mac.green,
                    'fair' => mac.accent,
                    _ => mac.orange,
                  },
                  count: book.ofTier(option.id).length,
                  selected: _tier == option.id,
                  onTap: () => setState(() => _tier = option.id),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              SizedBox(
                width: 170,
                child: MacField(
                  controller: _search,
                  hint: 'لټون…',
                  prefix:
                      Icon(Icons.search_rounded, size: 14, color: mac.text3),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (tier != null) ...[
            const SizedBox(height: 9),
            Text(tier.note,
                style: TextStyle(fontSize: 11.5, color: mac.text3)),
          ],
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) => _IdentityRow(
                profile: shown[index],
                selected: shown[index].id == _chosen,
                mine: shown[index].id == widget.account.fingerprintId,
                onTap: () => setState(() => _chosen = shown[index].id),
              ),
            ),
          ),
        ],
      ),
      actions: [
        MacButton(label: 'بندول', onPressed: () => Navigator.pop(context)),
        const SizedBox(width: 8),
        MacButton(
          label: 'وټاکه',
          style: MacButtonStyle.primary,
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(context, _chosen),
        ),
      ],
    );
  }
}

/// Why this exists at all, in two lines, where the decision is made.
class _WhyBox extends StatelessWidget {
  const _WhyBox();

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: mac.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(MacRadius.row),
        border: Border.all(color: mac.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 15, color: mac.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'هر اکاونټ ته د جوړېدو پر مهال خپله پېژندګلوي ورکول کېږي او تل '
              'همدا یوه پاتې کېږي. بدلول یې یوازې هغه وخت په کار دي چې دوه '
              'اکاونټه یوه وسیله ګډه کاروي — ځکه وسیله چې هره اونۍ بدلېږي، '
              'له هغې څخه ډېره جلبِ‌پام کوي چې هېڅکله نه بدلېږي.',
              style: TextStyle(fontSize: 11.5, height: 1.55, color: mac.text2),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.profile,
    required this.selected,
    required this.mine,
    required this.onTap,
  });

  final BrowserIdentity profile;
  final bool selected;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final taken = profile.usedBy > 0 && !mine;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? mac.accent.withValues(alpha: 0.10) : mac.fill,
          borderRadius: BorderRadius.circular(MacRadius.row),
          border: Border.all(
            color: selected ? mac.accent : mac.hairline,
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Icon(
              profile.mobile
                  ? Icons.smartphone_rounded
                  : Icons.laptop_mac_rounded,
              size: 16,
              color: selected ? mac.accent : mac.text3,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: mac.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // The numbers are read left to right even inside a
                    // right-to-left line, or "1920×1080" arrives backwards.
                    '\u2066${profile.screen}\u2069 · ${profile.cores} هستې'
                    '${profile.memory == null ? '' : ' · \u2066${profile.memory} GB\u2069'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: mac.text3),
                  ),
                ],
              ),
            ),
            if (mine)
              MacPill('اوسنی', color: mac.accent)
            else if (taken)
              MacPill('${profile.usedBy} اکاونټه', color: mac.orange),
          ],
        ),
      ),
    );
  }
}
