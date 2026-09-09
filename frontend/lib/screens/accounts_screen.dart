import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/account_dialogs.dart';
import '../widgets/mac_widgets.dart';
import 'dashboard_screen.dart' show relativeTime;
import 'shell.dart';

/// Saved sessions: sign in once, every later run reuses the cookies.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  List<String> _tabIds = const [];

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  /// The tab bar shows every category, so an empty one can still be opened.
  void _syncTabs(List<AccountCategory> categories) {
    final ids = categories.map((c) => c.id).toList();
    if (ids.length == _tabIds.length && ids.join() == _tabIds.join()) return;
    final previous = _tabs?.index ?? 0;
    _tabs?.dispose();
    _tabIds = ids;
    _tabs = TabController(
      length: ids.length,
      vsync: this,
      initialIndex: previous < ids.length ? previous : 0,
    );
    _tabs!.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final book = state.accounts;
    final categories = book.categories.where((c) => c.enabled).toList();

    if (categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    _syncTabs(categories);
    final controller = _tabs!;
    final current = categories[controller.index.clamp(0, categories.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 0),
          child: PageHeader(
            title: 'اکاونټونه',
            subtitle: book.total == 0
                ? 'یو ځل ننوځئ — بیا به هېڅکله پټنوم ونه غواړي'
                : '${book.total} خوندي شوي اکاونټه · د سکریپټ چلولو پر مهال یې وټاکئ',
            actions: [
              MacButton(
                label: 'نوی اکاونټ زیاتول',
                icon: Icons.person_add_alt_1_rounded,
                style: MacButtonStyle.primary,
                onPressed: state.busy ? null : () => addAccountFlow(context),
              ),
            ],
          ),
        ),
        if (state.session == SessionState.loggingIn)
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 14),
            child: _LoginBanner(state: state),
          ),
        _CategoryTabs(controller: controller, categories: categories, book: book),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [
              for (final category in categories)
                _CategoryTab(category: category, book: book, state: state),
            ],
          ),
        ),
        _Footer(category: current, state: state),
      ],
    );
  }
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.controller,
    required this.categories,
    required this.book,
  });

  final TabController controller;
  final List<AccountCategory> categories;
  final AccountBook book;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: mac.hairline, width: 0.8)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        labelColor: mac.accent,
        unselectedLabelColor: mac.text2,
        indicatorColor: mac.accent,
        indicatorWeight: 2,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(mac.fill),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        tabs: [
          for (final category in categories)
            Tab(
              height: 42,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(category.name),
                  const SizedBox(width: 7),
                  _CountBadge(
                    used: book.of(category.id).length,
                    max: category.maxAccounts,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.used, required this.max});

  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final full = used >= max;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: used == 0
            ? mac.fill2
            : (full ? mac.orange.withOpacity(0.18) : mac.green.withOpacity(0.18)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$used/$max',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: used == 0 ? mac.text3 : (full ? mac.orange : mac.green),
        ),
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.category,
    required this.book,
    required this.state,
  });

  final AccountCategory category;
  final AccountBook book;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final accounts = book.of(category.id);
    if (accounts.isEmpty) {
      return _EmptyCategory(category: category, state: state);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 18, 26, 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 900 ? 3 : 2;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: 138,
            ),
            itemCount: accounts.length,
            itemBuilder: (context, index) => AccountCard(
              account: accounts[index],
              category: category,
              state: state,
            ),
          );
        },
      ),
    );
  }
}

class AccountCard extends StatefulWidget {
  const AccountCard({
    super.key,
    required this.account,
    required this.category,
    required this.state,
  });

  final Account account;
  final AccountCategory category;
  final AppState state;

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final account = widget.account;
    final color = categoryColor(mac, widget.category.color);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: mac.window,
          borderRadius: BorderRadius.circular(MacRadius.card),
          border: Border.all(
            color: _hover ? color.withOpacity(0.5) : mac.hairline,
            width: 0.8,
          ),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(categoryIcon(widget.category.id),
                      size: 18, color: Colors.white),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        account.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: mac.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account.displayName.isEmpty
                            ? widget.category.name
                            : account.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: mac.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                MacPill('ننوتی',
                    color: mac.green, background: mac.green.withOpacity(0.16)),
                const SizedBox(width: 8),
                MacPill('${account.cookieCount} کوکیز'),
                const Spacer(),
                Text(
                  account.lastUsedAt == null
                      ? 'لا نه دی کارول شوی'
                      : relativeTime(account.lastUsedAt),
                  style: TextStyle(fontSize: 11, color: mac.text3),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                MacButton(
                  label: 'نوم بدلول',
                  icon: Icons.edit_outlined,
                  onPressed: widget.state.busy ? null : () => _rename(context),
                ),
                const SizedBox(width: 7),
                MacButton(
                  label: '',
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'ړنګول',
                  onPressed: widget.state.busy ? null : () => _delete(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final label = await promptAccountLabel(context, widget.account.label);
    if (label != null && label.trim().isNotEmpty) {
      await widget.state.renameAccount(widget.account.id, label.trim());
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirmDeleteAccount(context, widget.account.label);
    if (ok) await widget.state.deleteAccount(widget.account.id);
  }
}

class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory({required this.category, required this.state});

  final AccountCategory category;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final color = categoryColor(mac, category.color);

    return Center(
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(categoryIcon(category.id), size: 30, color: color),
            ),
            const SizedBox(height: 16),
            Text('د ${category.name} هېڅ اکاونټ نشته',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: mac.text)),
            const SizedBox(height: 8),
            Text(
              'کله چې «نوی اکاونټ زیاتول» ووهئ، د ${category.name} د ننوتلو پاڼه '
              'په یوه کوچنۍ کړکۍ کې پرانیستل کېږي. تاسو یوازې ننوځئ — پروګرام '
              'بیا پخپله کوکیز اخلي، نو بل ځل پټنوم ته اړتیا نشته.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: mac.text2, height: 1.7),
            ),
            const SizedBox(height: 18),
            MacButton(
              label: 'د ${category.name} اکاونټ زیات کړه',
              icon: Icons.person_add_alt_1_rounded,
              style: MacButtonStyle.primary,
              large: true,
              onPressed: state.busy
                  ? null
                  : () => startLoginFor(context, category),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live state while the user is signing in, with the "I'm done" button.
class _LoginBanner extends StatefulWidget {
  const _LoginBanner({required this.state});

  final AppState state;

  @override
  State<_LoginBanner> createState() => _LoginBannerState();
}

class _LoginBannerState extends State<_LoginBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final started = widget.state.sessionStartedAt;
    if (started == null) return '۰۰:۰۰';
    final seconds = DateTime.now().difference(started).inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final category =
        widget.state.accounts.category(widget.state.pendingCategoryId ?? '');

    return MacCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      color: mac.accentSoft,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: mac.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'د ${category?.name ?? 'حساب'} د ننوتلو کړکۍ پرانیستې ده',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: mac.text),
                ),
                const SizedBox(height: 2),
                Text(
                  'هلته خپل حساب ته ننوځئ. پروګرام پخپله ننوتل پېژني او کوکیز '
                  'خوندي کوي — که یې پېژندل ونه شول، دلته «ننوتم» ووهئ.',
                  style: TextStyle(fontSize: 11.5, color: mac.text2, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          MacPill(_elapsed, color: mac.accent, background: mac.window),
          const SizedBox(width: 10),
          MacButton(
            label: 'ننوتم — کوکیز واخله',
            icon: Icons.check_rounded,
            style: MacButtonStyle.primary,
            onPressed: widget.state.finishLogin,
          ),
        ],
      ),
    );
  }
}

/// Per-category limit control, pinned to the bottom of the page.
class _Footer extends StatelessWidget {
  const _Footer({required this.category, required this.state});

  final AccountCategory category;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final used = state.accounts.of(category.id).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      decoration: BoxDecoration(
        color: mac.sidebar,
        border: Border(top: BorderSide(color: mac.hairline, width: 0.8)),
      ),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, size: 16, color: mac.text2),
          const SizedBox(width: 9),
          Text('د ${category.name} حد اکثر اکاونټونه',
              style: TextStyle(fontSize: 12.5, color: mac.text)),
          const SizedBox(width: 12),
          MacIconButton(
            icon: Icons.remove_rounded,
            tooltip: 'کم کړه',
            onPressed: (category.maxAccounts <= 1 || category.maxAccounts <= used)
                ? null
                : () => state.setCategoryLimit(
                    category.id, category.maxAccounts - 1),
          ),
          SizedBox(
            width: 30,
            child: Text('${category.maxAccounts}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: mac.text)),
          ),
          MacIconButton(
            icon: Icons.add_rounded,
            tooltip: 'زیات کړه',
            onPressed: category.maxAccounts >= 20
                ? null
                : () => state.setCategoryLimit(
                    category.id, category.maxAccounts + 1),
          ),
          const SizedBox(width: 14),
          Text('اوس $used کارېږي',
              style: TextStyle(fontSize: 11.5, color: mac.text2)),
          const Spacer(),
          Icon(Icons.lock_outline_rounded, size: 15, color: mac.text3),
          const SizedBox(width: 7),
          Text(
            'کوکیز ستاسو په کمپیوټر کې خوندي دي — پټنومونه هېڅکله نه ذخیره کېږي',
            style: TextStyle(fontSize: 11.5, color: mac.text3),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ helpers

IconData categoryIcon(String id) {
  switch (id) {
    case 'facebook':
      return Icons.facebook_rounded;
    case 'x':
      return Icons.close_rounded;
    case 'instagram':
      return Icons.camera_alt_outlined;
    case 'google':
      return Icons.g_mobiledata_rounded;
    case 'linkedin':
      return Icons.work_outline_rounded;
    case 'youtube':
      return Icons.play_circle_outline_rounded;
    case 'tiktok':
      return Icons.music_note_rounded;
    case 'telegram':
      return Icons.send_rounded;
    default:
      return Icons.public_rounded;
  }
}

Color categoryColor(MacPalette mac, String key) {
  switch (key) {
    case 'pink':
      return mac.pink;
    case 'orange':
      return mac.orange;
    case 'purple':
      return mac.purple;
    case 'teal':
      return mac.teal;
    case 'green':
      return mac.green;
    case 'gray':
      return mac.text2;
    default:
      return mac.accent;
  }
}
