import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/security.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import 'dialogs.dart';
import 'mac_widgets.dart';
import 'security_dialogs.dart';

/// Taking data out of the app and putting it back in.
///
/// One panel serves all three pages, because the question is the same one
/// every time: which rows, in what shape, and — since a file on disk is a copy
/// nobody is guarding — does it carry the passwords. The answer to the last
/// one is no unless it is chosen on purpose, and either way the password is
/// asked for before anything is written.
class TransferKind {
  const TransferKind({
    required this.id,
    required this.title,
    required this.exportNote,
    required this.importNote,
    required this.formats,
    this.secretLabel = '',
    this.secretNote = '',
    this.cookieLabel = '',
    this.cookieNote = '',
    this.importHint = '',
    this.canImport = true,
  });

  /// accounts · proxies · scripts
  final String id;
  final String title;
  final String exportNote;
  final String importNote;

  /// Format id → what to call it.
  final Map<String, String> formats;
  final String secretLabel;
  final String secretNote;

  /// Only accounts have a session to carry.
  final String cookieLabel;
  final String cookieNote;
  final String importHint;
  final bool canImport;

  static const accounts = TransferKind(
    id: 'accounts',
    title: 'اکاونټونه',
    exportNote: 'نوم، کټګوري، د کوکیزو حالت، پروکسي او پېژندګلوي — هر اکاونټ '
        'یوه کرښه، په CSV کې چې اېکسل یې پرانیزي.',
    importNote: 'د CSV فایل کرښې بېرته اکاونټونو ته اړوي. که فایل کوکیز هم '
        'ولري، اکاونټ له خپلې ناستې سره راځي — بیا ننوتل نه غواړي.',
    formats: {'csv': 'CSV (اېکسل)'},
    secretLabel: 'کارن‌نومونه او پټنومونه هم ورسره',
    secretNote: 'فایل به بیا د اکاونټونو پټنومونه په ساده متن ولري. یوازې هغه '
        'وخت یې وکاروئ چې فایل خوندي ځای ته وړئ.',
    cookieLabel: 'کوکیز هم ورسره وساته',
    cookieNote: 'اکاونټ به بل کمپیوټر ته هم ننوتی ولاړ شي — خو څوک چې فایل '
        'ولري، هغه هم ننوتلی دی. له پټنوم هم دا خطرناکه ده.',
    importHint: 'category,label,display_name,proxy_address,…',
  );

  static const proxies = TransferKind(
    id: 'proxies',
    title: 'پروکسي',
    exportNote: 'پته، پورټ، حالت، وتنځی IP او ځای — د هرې پروکسي یوه کرښه.',
    importNote: 'CSV یا هماغه ساده لیست چې خرڅوونکي درکړی — دواړه پېژندل کېږي.',
    formats: {'csv': 'CSV (اېکسل)'},
    secretLabel: 'د پروکسیو پټنومونه هم ورسره',
    secretNote: 'پرته له پټنوم، فایل بېرته د کارولو وړ نه دی — خو د لېږلو '
        'لپاره خوندي دی.',
    importHint: 'host:port:user:pass  ·  یا د CSV فایل',
  );

  static const scripts = TransferKind(
    id: 'scripts',
    title: 'سکریپټونه',
    exportNote: 'JSON بیرته راوړل کېږي؛ Python او JavaScript د چلولو وړ کوډ '
        'دی چې له دې پروګرام بهر هم چلېږي.',
    importNote: 'یوازې هغه JSON چې له همدې ځایه وتلی وي.',
    formats: {
      'json': 'JSON (بیرته راوړل کېږي)',
      'py': 'Python (Selenium)',
      'js': 'JavaScript (Playwright)',
      'csv': 'CSV (یوازې لنډیز)',
    },
    importHint: '{"kind": "webscripts/scripts", …}',
  );
}

Future<void> transferFlow(
  BuildContext context,
  TransferKind kind, {
  List<String>? ids,
}) async {
  final state = context.read<AppState>();
  await showMacSheet<void>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: _TransferSheet(kind: kind, ids: ids),
    ),
  );
}

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.kind, this.ids});

  final TransferKind kind;

  /// Only these rows, when the page had a selection. Null means everything.
  final List<String>? ids;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  late String _format = widget.kind.formats.keys.first;
  bool _includeSecrets = false;
  bool _includeCookies = false;
  bool _onlySelected = true;
  bool _working = false;

  final _paste = TextEditingController();
  final _path = TextEditingController();

  TransferResult? _exported;
  TransferResult? _imported;

  @override
  void dispose() {
    _paste.dispose();
    _path.dispose();
    super.dispose();
  }

  List<String>? get _ids {
    final chosen = widget.ids;
    if (chosen == null || chosen.isEmpty || !_onlySelected) return null;
    return chosen;
  }

  Future<void> _export() async {
    final proof = await askForCode(
      context,
      title: 'د ${widget.kind.title} وېستل',
      reason: _includeSecrets || _includeCookies
          ? 'فایل به پټنومونه یا کوکیز ولري — نو لومړی خپل پټنوم ولیکئ.'
          : 'معلومات فایل ته وځي، نو لومړی خپل پټنوم ولیکئ.',
      icon: Icons.file_download_outlined,
    );
    if (proof == null || !mounted) return;
    setState(() {
      _working = true;
      _exported = null;
    });
    final result = await context.read<AppState>().exportData(
          widget.kind.id,
          proof: proof,
          ids: _ids,
          format: _format,
          includeSecrets: _includeSecrets,
          includeCookies: _includeCookies,
        );
    if (mounted) {
      setState(() {
        _working = false;
        _exported = result;
      });
    }
  }

  Future<void> _import() async {
    if (_paste.text.trim().isEmpty && _path.text.trim().isEmpty) return;
    final proof = await askForCode(
      context,
      title: 'د ${widget.kind.title} راوړل',
      reason: 'راوړل ستاسو معلومات بدلوي، نو لومړی خپل پټنوم ولیکئ.',
      icon: Icons.file_upload_outlined,
    );
    if (proof == null || !mounted) return;
    setState(() {
      _working = true;
      _imported = null;
    });
    final result = await context.read<AppState>().importData(
          widget.kind.id,
          proof: proof,
          text: _paste.text,
          path: _path.text.trim(),
        );
    if (mounted) {
      setState(() {
        _working = false;
        _imported = result;
        if (result != null) _paste.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 720;
        final out = _ExportSide(
          kind: widget.kind,
          format: _format,
          onFormat: (value) => setState(() => _format = value),
          includeSecrets: _includeSecrets,
          onSecrets: (value) => setState(() => _includeSecrets = value),
          includeCookies: _includeCookies,
          onCookies: (value) => setState(() => _includeCookies = value),
          selection: widget.ids,
          onlySelected: _onlySelected,
          onOnlySelected: (value) => setState(() => _onlySelected = value),
          working: _working,
          result: _exported,
          onRun: _export,
        );
        final back = widget.kind.canImport
            ? _ImportSide(
                kind: widget.kind,
                paste: _paste,
                path: _path,
                working: _working,
                result: _imported,
                onRun: _import,
              )
            : const SizedBox.shrink();
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [out, const SizedBox(height: 14), back],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: out),
            const SizedBox(width: 14),
            Expanded(child: back),
          ],
        );
      },
    );

    return MacSheet(
      title: 'وړل او راوړل — ${widget.kind.title}',
      subtitle: 'فایلونه ستاسو په کمپیوټر کې پاتې کېږي؛ هېڅ ځای ته نه لېږل کېږي.',
      icon: Icons.swap_vert_rounded,
      width: 760,
      body: body,
      actions: [
        MacButton(label: 'بندول', onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}

class _ExportSide extends StatelessWidget {
  const _ExportSide({
    required this.kind,
    required this.format,
    required this.onFormat,
    required this.includeSecrets,
    required this.onSecrets,
    required this.includeCookies,
    required this.onCookies,
    required this.selection,
    required this.onlySelected,
    required this.onOnlySelected,
    required this.working,
    required this.result,
    required this.onRun,
  });

  final TransferKind kind;
  final String format;
  final ValueChanged<String> onFormat;
  final bool includeSecrets;
  final ValueChanged<bool> onSecrets;
  final bool includeCookies;
  final ValueChanged<bool> onCookies;
  final List<String>? selection;
  final bool onlySelected;
  final ValueChanged<bool> onOnlySelected;
  final bool working;
  final TransferResult? result;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final chosen = selection?.length ?? 0;

    return _Side(
      icon: Icons.file_download_outlined,
      title: 'وېستل',
      note: kind.exportNote,
      children: [
        if (kind.formats.length > 1) ...[
          Text('بڼه',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: mac.text2)),
          const SizedBox(height: 7),
          for (final entry in kind.formats.entries) ...[
            _Choice(
              label: entry.value,
              selected: format == entry.key,
              onTap: () => onFormat(entry.key),
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 6),
        ],
        if (chosen > 0)
          _Toggle(
            label: 'یوازې ټاکل شوي ($chosen)',
            note: onlySelected ? '' : 'ټول به ووځي.',
            value: onlySelected,
            onChanged: onOnlySelected,
          ),
        if (chosen > 0) const SizedBox(height: 8),
        if (kind.secretLabel.isNotEmpty)
          _Toggle(
            label: kind.secretLabel,
            note: kind.secretNote,
            value: includeSecrets,
            onChanged: onSecrets,
            warn: true,
          ),
        if (kind.cookieLabel.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Toggle(
            label: kind.cookieLabel,
            note: kind.cookieNote,
            value: includeCookies,
            onChanged: onCookies,
            warn: true,
          ),
        ],
        const SizedBox(height: 14),
        MacButton(
          label: working ? 'لیکل کېږي…' : 'فایل جوړ کړه',
          icon: Icons.save_alt_rounded,
          style: MacButtonStyle.primary,
          expand: true,
          onPressed: working ? null : onRun,
        ),
        if (result != null) ...[
          const SizedBox(height: 12),
          _Done(
            title: '${result!.count} دانې ولیکل شوې',
            lines: result!.files,
            folder: result!.folder,
          ),
        ],
      ],
    );
  }
}

class _ImportSide extends StatelessWidget {
  const _ImportSide({
    required this.kind,
    required this.paste,
    required this.path,
    required this.working,
    required this.result,
    required this.onRun,
  });

  final TransferKind kind;
  final TextEditingController paste;
  final TextEditingController path;
  final bool working;
  final TransferResult? result;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return _Side(
      icon: Icons.file_upload_outlined,
      title: 'راوړل',
      note: kind.importNote,
      children: [
        Container(
          decoration: BoxDecoration(
            color: mac.fill,
            borderRadius: BorderRadius.circular(MacRadius.row),
            border: Border.all(color: mac.hairline, width: 0.8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: paste,
              maxLines: 6,
              minLines: 6,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration.collapsed(
                hintText: kind.importHint,
                hintStyle: TextStyle(fontSize: 11.5, color: mac.text3),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'یا د فایل بشپړه لاره ولیکئ',
          style: TextStyle(fontSize: 11.5, color: mac.text2),
        ),
        const SizedBox(height: 6),
        Directionality(
          textDirection: TextDirection.ltr,
          child: MacField(
            controller: path,
            hint: r'C:\Users\...\accounts.csv',
            prefix:
                Icon(Icons.folder_open_outlined, size: 14, color: mac.text3),
          ),
        ),
        const SizedBox(height: 14),
        MacButton(
          label: working ? 'راوړل کېږي…' : 'راوړه',
          icon: Icons.playlist_add_rounded,
          expand: true,
          onPressed: working ? null : onRun,
        ),
        if (result != null) ...[
          const SizedBox(height: 12),
          _Done(
            title: result!.added == 0
                ? 'هېڅ نوی څه رانغی'
                : '${result!.added} دانې راغلې'
                    '${result!.duplicates > 0 ? ' · ${result!.duplicates} تکرار' : ''}',
            lines: result!.problems,
            note: result!.note,
            bad: result!.added == 0 && result!.problems.isNotEmpty,
          ),
        ],
      ],
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.icon,
    required this.title,
    required this.note,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: mac.window,
        borderRadius: BorderRadius.circular(MacRadius.card),
        border: Border.all(color: mac.hairline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: mac.accent),
              const SizedBox(width: 9),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: mac.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(note,
              style: TextStyle(fontSize: 11.5, height: 1.6, color: mac.text3)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
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
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 15,
              color: selected ? mac.accent : mac.text3,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 12.5, color: mac.text)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.note,
    required this.value,
    required this.onChanged,
    this.warn = false,
  });

  final String label;
  final String note;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final loud = warn && value;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: loud ? mac.orange.withValues(alpha: 0.08) : mac.fill,
        borderRadius: BorderRadius.circular(MacRadius.row),
        border: Border.all(
          color: loud ? mac.orange.withValues(alpha: 0.32) : mac.hairline,
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12.5, color: mac.text)),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: loud ? mac.orange : mac.text3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          MacSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({
    required this.title,
    this.lines = const [],
    this.folder = '',
    this.note = '',
    this.bad = false,
  });

  final String title;
  final List<String> lines;
  final String folder;
  final String note;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final colour = bad ? mac.red : mac.green;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MacRadius.row),
        border: Border.all(color: colour.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                bad ? Icons.error_outline_rounded : Icons.check_circle_outline,
                size: 15,
                color: colour,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: mac.text,
                  ),
                ),
              ),
              if (folder.isNotEmpty)
                MacIconButton(
                  icon: Icons.copy_rounded,
                  tooltip: 'لاره کاپي کړه',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: folder)),
                ),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note,
                style:
                    TextStyle(fontSize: 11, height: 1.5, color: mac.text2)),
          ],
          for (final line in lines.take(6)) ...[
            const SizedBox(height: 5),
            Directionality(
              textDirection:
                  line.startsWith('/') || line.contains(r':\')
                      ? TextDirection.ltr
                      : TextDirection.rtl,
              child: Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontFamily: 'monospace', color: mac.text2),
              ),
            ),
          ],
          if (lines.length > 6) ...[
            const SizedBox(height: 5),
            Text('… او ${lines.length - 6} نور',
                style: TextStyle(fontSize: 11, color: mac.text3)),
          ],
        ],
      ),
    );
  }
}
