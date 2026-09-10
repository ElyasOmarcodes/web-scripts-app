import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/script.dart';
import '../screens/accounts_screen.dart'
    show CookieLight, categoryColor, categoryIcon;
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import 'dialogs.dart';
import 'mac_widgets.dart';

/// "Which service is this account for?" — then opens its login page.
Future<void> addAccountFlow(BuildContext context) async {
  final state = context.read<AppState>();
  final picked = await showMacSheet<AccountCategory>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const _ServicePickerSheet(),
    ),
  );
  if (picked == null) return;
  if (!context.mounted) return;
  await startLoginFor(context, picked);
}

/// Asks for a label, then opens the small sign-in window.
Future<void> startLoginFor(
    BuildContext context, AccountCategory category) async {
  final state = context.read<AppState>();
  final used = state.accounts.of(category.id).length;

  final label = await promptAccountLabel(
    context,
    '${category.name} ${used + 1}',
    title: 'د ${category.name} نوی اکاونټ',
    subtitle: 'یو نوم ورکړئ چې وروسته یې وپېژنئ (مثلاً «کاري» یا «شخصي»)',
  );
  if (label == null) return;
  await state.startLogin(category.id, label: label.trim());
}

class _ServicePickerSheet extends StatelessWidget {
  const _ServicePickerSheet();

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();
    final book = state.accounts;
    final categories = book.categories.where((c) => c.enabled).toList();

    return MacSheet(
      title: 'د کوم سایټ اکاونټ؟',
      subtitle: 'د هغه سایټ د ننوتلو پاڼه به پرانیستل شي',
      icon: Icons.person_add_alt_1_rounded,
      width: 560,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              // Icon + two lines of text; 92 clipped the counter by ~5px.
              mainAxisExtent: 102,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final used = book.of(category.id).length;
              return _ServiceTile(
                category: category,
                used: used,
                onTap: used >= category.maxAccounts
                    ? null
                    : () => Navigator.of(context).pop(category),
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 15, color: mac.text3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'پټنوم یوازې تاسو په براوزر کې لیکئ — پروګرام یې نه ویني او نه '
                  'یې ذخیره کوي. یوازې د ناستې کوکیز خوندي کېږي.',
                  style:
                      TextStyle(fontSize: 11.5, color: mac.text2, height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        MacButton(
          label: 'لغوه',
          large: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatefulWidget {
  const _ServiceTile({
    required this.category,
    required this.used,
    this.onTap,
  });

  final AccountCategory category;
  final int used;
  final VoidCallback? onTap;

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final color = categoryColor(mac, widget.category.color);
    final full = widget.onTap == null;

    return MouseRegion(
      cursor: full ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hover && !full ? color.withValues(alpha: 0.08) : mac.window,
            borderRadius: BorderRadius.circular(MacRadius.card),
            border: Border.all(
              color:
                  _hover && !full ? color.withValues(alpha: 0.6) : mac.hairline,
              width: 0.8,
            ),
          ),
          child: Opacity(
            opacity: full ? 0.45 : 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(categoryIcon(widget.category.id),
                      size: 17, color: Colors.white),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: mac.text),
                ),
                const SizedBox(height: 2),
                Text(
                  full
                      ? 'ډک دی'
                      : '${widget.used}/${widget.category.maxAccounts}',
                  style: TextStyle(fontSize: 11, color: mac.text3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> promptAccountLabel(
  BuildContext context,
  String initialValue, {
  String title = 'د اکاونټ نوم',
  String? subtitle,
}) {
  return promptText(
    context,
    title: title,
    subtitle: subtitle,
    initialValue: initialValue,
    label: 'نوم',
  );
}

Future<bool> confirmDeleteAccount(BuildContext context, String label) {
  return confirmSheet(
    context,
    title: 'اکاونټ ړنګول',
    message: '«$label» ړنګ کړم؟ د هغه کوکیز او د براوزر پروفایل هم ړنګېږي، '
        'نو بیا به ننوتل پکار وي.',
    confirmLabel: 'ړنګ کړه',
  );
}

/// "Run as which account?" — shown before a run when accounts exist.
/// Compact "run/record as" selector, for sheets that only need one line.
class AccountDropdown extends StatelessWidget {
  const AccountDropdown({
    super.key,
    required this.book,
    required this.value,
    required this.onChanged,
  });

  final AccountBook book;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final accounts = book.usable;
    // A saved account may have been deleted since it was picked.
    final effective = accounts.any((a) => a.id == value) ? value : null;

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: mac.window,
        borderRadius: BorderRadius.circular(MacRadius.control),
        border: Border.all(color: mac.hairline, width: 0.8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: effective,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          icon: Icon(Icons.unfold_more_rounded, size: 15, color: mac.text3),
          style: TextStyle(fontSize: 13, color: mac.text),
          dropdownColor: mac.window,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Row(
                children: [
                  Icon(Icons.no_accounts_rounded, size: 15, color: mac.text3),
                  const SizedBox(width: 8),
                  const Text('بې اکاونټه'),
                ],
              ),
            ),
            ...accounts.map(
              (account) => DropdownMenuItem<String?>(
                value: account.id,
                child: Row(
                  children: [
                    Icon(
                      categoryIcon(account.category),
                      size: 15,
                      color: categoryColor(
                        mac,
                        book.category(account.category)?.color ?? 'blue',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${account.label} · '
                        '${book.category(account.category)?.name ?? account.category}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class AccountPickerSheet extends StatefulWidget {
  const AccountPickerSheet({
    super.key,
    required this.book,
    required this.scriptName,
    this.initial,
  });

  final AccountBook book;
  final String scriptName;
  final String? initial;

  @override
  State<AccountPickerSheet> createState() => _AccountPickerSheetState();
}

class _AccountPickerSheetState extends State<AccountPickerSheet> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final accounts = widget.book.usable;

    return MacSheet(
      title: 'د کوم اکاونټ په نامه یې وچلوم؟',
      subtitle: widget.scriptName,
      icon: Icons.switch_account_rounded,
      width: 520,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: SingleChildScrollView(
              child: MacGroup(
                children: [
                  _AccountOption(
                    icon: Icons.no_accounts_rounded,
                    color: mac.text2,
                    title: 'بې اکاونټه',
                    subtitle: 'عادي پروفایل وکاروه',
                    selected: _selected == null,
                    onTap: () => setState(() => _selected = null),
                  ),
                  for (final account in accounts)
                    _AccountOption(
                      icon: categoryIcon(account.category),
                      color: categoryColor(
                        mac,
                        widget.book.category(account.category)?.color ?? 'blue',
                      ),
                      title: account.label,
                      subtitle:
                          '${widget.book.category(account.category)?.name ?? account.category}'
                          ' · ${account.cookieCount} کوکیز',
                      selected: _selected == account.id,
                      onTap: () => setState(() => _selected = account.id),
                    ),
                ],
              ),
            ),
          ),
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'لا هېڅ اکاونټ خوندي شوی نه دی — د «اکاونټونه» پاڼې څخه یې زیات کړئ.',
                style: TextStyle(fontSize: 11.5, color: mac.text2, height: 1.5),
              ),
            ),
        ],
      ),
      actions: [
        MacButton(
          label: 'چلول',
          icon: Icons.play_arrow_rounded,
          style: MacButtonStyle.primary,
          large: true,
          onPressed: () => Navigator.of(context).pop(_AccountChoice(_selected)),
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

class _AccountChoice {
  const _AccountChoice(this.accountId);

  final String? accountId;
}

class _AccountOption extends StatelessWidget {
  const _AccountOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return MacRow(
      onTap: onTap,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? mac.accent : Colors.transparent,
              border: Border.all(
                color: selected ? mac.accent : mac.text3,
                width: 1.2,
              ),
            ),
            child: selected
                ? Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 11),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: Colors.white),
          ),
        ],
      ),
      title: title,
      subtitle: subtitle,
    );
  }
}

/// True when the run should go ahead. Sets [accountId] from the picker.
Future<({bool go, String? accountId})> resolveRunAccount(
  BuildContext context,
  WebScript script,
) async {
  final state = context.read<AppState>();
  if (state.accounts.usable.isEmpty) return (go: true, accountId: null);

  final choice = await showMacSheet<_AccountChoice>(
    context,
    AccountPickerSheet(book: state.accounts, scriptName: script.name),
  );
  if (choice == null) return (go: false, accountId: null);
  return (go: true, accountId: choice.accountId);
}

/// Pick several accounts at once, one category at a time.
///
/// Each category is a tab holding only its own accounts, with a search box
/// above the list that searches *inside the open category* — a task on X
/// should never have to scroll past the Facebook accounts to find one.
class AccountMultiPicker extends StatefulWidget {
  const AccountMultiPicker({
    super.key,
    required this.book,
    required this.selected,
    required this.onChanged,
  });

  final AccountBook book;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  State<AccountMultiPicker> createState() => _AccountMultiPickerState();
}

class _AccountMultiPickerState extends State<AccountMultiPicker>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  List<String> _tabIds = const [];
  final _search = TextEditingController();

  @override
  void dispose() {
    _tabs?.dispose();
    _search.dispose();
    super.dispose();
  }

  void _syncTabs(List<AccountCategory> categories) {
    final ids = categories.map((c) => c.id).toList();
    if (_tabIds.length == ids.length && _tabIds.join() == ids.join()) return;
    final previous = _tabs?.index ?? 0;
    _tabs?.dispose();
    _tabIds = ids;
    _tabs = TabController(
      length: ids.length,
      vsync: this,
      initialIndex: previous < ids.length ? previous : 0,
    );
    // Searching is per category, so the box empties when the tab changes.
    _tabs!.addListener(() {
      if (!_tabs!.indexIsChanging) return;
      _search.clear();
      setState(() {});
    });
  }

  void _toggle(String id) {
    final next = List<String>.from(widget.selected);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    // Only categories that actually hold a usable account are worth a tab.
    final categories = widget.book.categories
        .where((c) => widget.book.of(c.id).isNotEmpty)
        .toList();

    if (categories.isEmpty) {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: mac.fill,
          borderRadius: BorderRadius.circular(MacRadius.card),
        ),
        child: Text(
          'لا هېڅ اکاونټ نشته — د «اکاونټونه» پاڼې څخه یو زیات کړئ.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: mac.text2),
        ),
      );
    }

    _syncTabs(categories);
    final controller = _tabs!;
    final current =
        categories[controller.index.clamp(0, categories.length - 1)];
    final needle = _search.text.trim().toLowerCase();
    final accounts = widget.book
        .of(current.id)
        .where((a) =>
            needle.isEmpty ||
            a.label.toLowerCase().contains(needle) ||
            a.displayName.toLowerCase().contains(needle))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: mac.window,
        borderRadius: BorderRadius.circular(MacRadius.card),
        border: Border.all(color: mac.hairline, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 34,
            child: TabBar(
              controller: controller,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: mac.hairline,
              indicatorColor: mac.accent,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: mac.text,
              unselectedLabelColor: mac.text2,
              labelStyle:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 12.5),
              tabs: [
                for (final category in categories)
                  Tab(
                    height: 33,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(categoryIcon(category.id),
                            size: 13,
                            color: categoryColor(mac, category.color)),
                        const SizedBox(width: 6),
                        Text(category.name),
                        const SizedBox(width: 5),
                        Text('${widget.book.of(category.id).length}',
                            style: TextStyle(fontSize: 11, color: mac.text3)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: MacField(
              controller: _search,
              hint: 'په «${current.name}» کې لټون…',
              prefix: Icon(Icons.search_rounded, size: 14, color: mac.text3),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: accounts.isEmpty
                ? Center(
                    child: Text(
                      needle.isEmpty
                          ? 'دې کټګورۍ کې اکاونټ نشته'
                          : 'هېڅ اکاونټ ونه موندل شو',
                      style: TextStyle(fontSize: 12, color: mac.text2),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: accounts.length,
                    itemBuilder: (context, index) {
                      final account = accounts[index];
                      return _PickRow(
                        account: account,
                        color: categoryColor(mac, current.color),
                        checked: widget.selected.contains(account.id),
                        onTap: () => _toggle(account.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.account,
    required this.color,
    required this.checked,
    required this.onTap,
  });

  final Account account;
  final Color color;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: checked ? mac.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(MacRadius.row),
          ),
          child: Row(
            children: [
              Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                  color: checked ? mac.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: checked ? mac.accent : mac.text3,
                    width: 1.2,
                  ),
                ),
                child: checked
                    ? const Icon(Icons.check_rounded,
                        size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Icon(categoryIcon(account.category), size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  account.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: mac.text),
                ),
              ),
              // Whether this account's session is still alive matters most
              // right here, where it is being picked for a task.
              CookieLight(
                state: account.cookieState,
                note: account.cookieNote,
                checkedAt: account.cookieCheckedAt,
                size: 8,
              ),
              const SizedBox(width: 8),
              Text(
                '${account.cookieCount} کوکیز',
                style: TextStyle(fontSize: 11, color: mac.text3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
