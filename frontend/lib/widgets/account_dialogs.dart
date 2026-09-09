import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/script.dart';
import '../screens/accounts_screen.dart' show categoryColor, categoryIcon;
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
