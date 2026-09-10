import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import 'account_dialogs.dart';
import 'dialogs.dart';
import 'mac_widgets.dart';

/// Create a task, or change one. Everything a task holds lives in this sheet.
Future<void> taskEditorFlow(
  BuildContext context, {
  WebTask? task,
  String? scriptId,
}) async {
  final state = context.read<AppState>();
  final saved = await showMacSheet<WebTask>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: _TaskSheet(task: task, initialScriptId: scriptId),
    ),
  );
  if (saved == null) return;

  final fields = saved.toJson();
  if (task == null) {
    await state.createTask(fields);
  } else {
    await state.updateTask(task.id, fields);
  }
}

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({this.task, this.initialScriptId});

  final WebTask? task;
  final String? initialScriptId;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final TextEditingController _name;
  late String _scriptId;
  late List<String> _accounts;
  late int _concurrency;
  late bool _stopOnError;
  late bool _keepOpen;
  late bool _hidden;
  late double _gap;
  String? _error;
  Map<String, dynamic>? _cost;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _name = TextEditingController(text: task?.name ?? 'نوی کار');
    _scriptId = task?.scriptId ?? widget.initialScriptId ?? '';
    _accounts = List<String>.from(task?.accountIds ?? const []);
    _concurrency = task?.concurrency ?? 1;
    _stopOnError = task?.stopOnError ?? false;
    _keepOpen = task?.keepOpen ?? false;
    _hidden = task?.headless ?? false;
    _gap = task?.gapSeconds ?? 3;
    _loadCost();
  }

  /// Ask the backend what this many windows would cost on this machine.
  Future<void> _loadCost() async {
    final info = await context
        .read<AppState>()
        .systemInfo(windows: _concurrency, headless: _hidden);
    if (mounted) setState(() => _cost = info);
  }

  void _setConcurrency(int value) {
    setState(() => _concurrency = value.clamp(1, 32));
    _loadCost();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'نوم اړین دی');
      return;
    }
    if (_scriptId.isEmpty) {
      setState(() => _error = 'یو سکریپټ وټاکئ');
      return;
    }
    if (_accounts.isEmpty) {
      setState(() => _error = 'لږ تر لږه یو اکاونټ وټاکئ');
      return;
    }
    Navigator.of(context).pop(
      (widget.task ?? const WebTask(id: '')).copyWith(
        name: name,
        scriptId: _scriptId,
        accountIds: _accounts,
        concurrency: _concurrency,
        stopOnError: _stopOnError,
        keepOpen: _keepOpen,
        headless: _hidden,
        gapSeconds: _gap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();

    return MacSheet(
      title: widget.task == null ? 'نوی کار' : 'د کار تنظیمات',
      subtitle: 'کوم سکریپټ، په کومو اکاونټونو، او څنګه',
      icon: Icons.checklist_rounded,
      width: 620,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetLabel('د کار نوم'),
          MacField(controller: _name, autofocus: widget.task == null),
          const SizedBox(height: 13),
          const SheetLabel('سکریپټ'),
          _ScriptPicker(
            value: _scriptId,
            onChanged: (value) => setState(() => _scriptId = value),
          ),
          const SizedBox(height: 13),
          SheetLabel('اکاونټونه (${_accounts.length} ټاکل شوي)'),
          SizedBox(
            height: 190,
            child: AccountMultiPicker(
              book: state.accounts,
              selected: _accounts,
              onChanged: (value) => setState(() => _accounts = value),
            ),
          ),
          const SizedBox(height: 13),
          const SheetLabel('څنګه دې وچلېږي؟'),
          MacSegmented<bool>(
            value: _hidden,
            items: const {
              false: 'بصري — براوزر ښکاري',
              true: 'پټ — بک ګراونډ کې',
            },
            onChanged: (value) {
              setState(() => _hidden = value);
              _loadCost();
            },
          ),
          const SizedBox(height: 5),
          Text(
            _hidden
                ? 'براوزر نه پرانیستل کېږي — پروسیسر ~۳۵٪ او حافظه ~۲۰٪ کمه کاروي، '
                    'خو ځینې سایټونه پټ براوزر اسانه پېژني.'
                : 'براوزر ښکاري، نو کار په خپلو سترګو ګورئ.',
            style: TextStyle(fontSize: 11.5, color: mac.text2, height: 1.5),
          ),
          const SizedBox(height: 13),
          const SheetLabel('په یو وخت کې څو اکاونټه؟'),
          _ConcurrencyPicker(
            value: _concurrency,
            accounts: _accounts.length,
            onChanged: _setConcurrency,
          ),
          const SizedBox(height: 8),
          _CostPanel(cost: _cost, windows: _concurrency),
          const SizedBox(height: 10),
          MacRow(
            title: 'د اکاونټونو تر منځ ځنډ',
            subtitle: 'یو له بل وروسته، چې یوځل ټول ونه لیدل شي',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MacIconButton(
                  icon: Icons.remove_rounded,
                  onPressed: _gap <= 0
                      ? null
                      : () => setState(() => _gap = (_gap - 1).clamp(0, 120)),
                ),
                SizedBox(
                  width: 66,
                  child: Text(
                    '${_gap.round()} ثانیې',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: mac.text),
                  ),
                ),
                MacIconButton(
                  icon: Icons.add_rounded,
                  onPressed: _gap >= 120
                      ? null
                      : () => setState(() => _gap = (_gap + 1).clamp(0, 120)),
                ),
              ],
            ),
          ),
          MacRow(
            title: 'په لومړۍ تېروتنه ودرېږه',
            subtitle: 'که بند وي، پاتې اکاونټونه بیا هم چلېږي',
            trailing: MacSwitch(
              value: _stopOnError,
              onChanged: (value) => setState(() => _stopOnError = value),
            ),
          ),
          MacRow(
            title: 'براوزر پرانیستی پرېږده',
            subtitle: 'د کار له پای ته رسېدو وروسته کړکۍ نه تړل کېږي',
            trailing: MacSwitch(
              value: _keepOpen,
              onChanged: (value) => setState(() => _keepOpen = value),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child:
                  Text(_error!, style: TextStyle(fontSize: 12, color: mac.red)),
            ),
        ],
      ),
      actions: [
        MacButton(
          label: widget.task == null ? 'جوړ یې کړه' : 'خوندي کړه',
          icon: Icons.check_rounded,
          style: MacButtonStyle.primary,
          large: true,
          onPressed: _submit,
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

/// Which recorded script this task runs.
class _ScriptPicker extends StatelessWidget {
  const _ScriptPicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final scripts = context.watch<AppState>().scripts;
    final effective = scripts.any((s) => s.id == value) ? value : '';

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: mac.window,
        borderRadius: BorderRadius.circular(MacRadius.control),
        border: Border.all(color: mac.hairline, width: 0.8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effective,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          icon: Icon(Icons.unfold_more_rounded, size: 15, color: mac.text3),
          style: TextStyle(fontSize: 13, color: mac.text),
          dropdownColor: mac.window,
          items: [
            DropdownMenuItem(
              value: '',
              child:
                  Text('— سکریپټ وټاکئ —', style: TextStyle(color: mac.text3)),
            ),
            ...scripts.map(
              (script) => DropdownMenuItem(
                value: script.id,
                child: Text(
                  '${script.name} · ${script.stepCount} ګامه',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

/// How many browsers work at once.
///
/// The common answers are one tap away, and any other number can be typed —
/// the machine decides what is sensible, not the app, and the panel under it
/// says what the chosen number costs.
class _ConcurrencyPicker extends StatelessWidget {
  const _ConcurrencyPicker({
    required this.value,
    required this.accounts,
    required this.onChanged,
  });

  final int value;
  final int accounts;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Row(
      children: [
        for (var count = 1; count <= 4; count++) ...[
          Expanded(
            child: _LaneOption(
              count: count,
              selected: value == count,
              onTap: () => onChanged(count),
            ),
          ),
          const SizedBox(width: 8),
        ],
        // Anything above four: the user's own number.
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            decoration: BoxDecoration(
              color: value > 4 ? mac.accentSoft : mac.fill,
              borderRadius: BorderRadius.circular(MacRadius.control),
              border: Border.all(
                color: value > 4 ? mac.accent : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MacIconButton(
                  icon: Icons.remove_rounded,
                  size: 15,
                  onPressed: value <= 1 ? null : () => onChanged(value - 1),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: mac.text,
                    ),
                  ),
                ),
                MacIconButton(
                  icon: Icons.add_rounded,
                  size: 15,
                  onPressed: value >= 32 ? null : () => onChanged(value + 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// What the chosen number of windows costs on *this* computer.
class _CostPanel extends StatelessWidget {
  const _CostPanel({required this.cost, required this.windows});

  final Map<String, dynamic>? cost;
  final int windows;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final estimate = cost?['estimate'] as Map<String, dynamic>?;
    final machine = cost?['machine'] as Map<String, dynamic>?;
    if (estimate == null || machine == null) {
      return Text(
        'د کمپیوټر د وس اندازه کول…',
        style: TextStyle(fontSize: 11.5, color: mac.text3),
      );
    }

    final load = (estimate['load'] as num? ?? 0).toDouble();
    final level = estimate['level'] as String? ?? 'easy';
    final color = switch (level) {
      'over' => mac.red,
      'busy' => mac.orange,
      _ => mac.green,
    };
    final cores = (machine['cores'] as num? ?? 0).toInt();
    final ram = (estimate['ram_needed_mb'] as num? ?? 0).toInt();
    final recommended = (estimate['recommended'] as num? ?? 1).toInt();
    final label = switch (level) {
      'over' => 'له وس زیات',
      'busy' => 'بار پرې لوېږي',
      _ => 'اسانه',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MacRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.memory_rounded, size: 15, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$windows کړکۍ ≈ '
                  '${(estimate['cores_needed'] as num).toStringAsFixed(1)} '
                  'هستې له $cores · ~$ram MB حافظه',
                  style: TextStyle(fontSize: 12, color: mac.text),
                ),
              ),
              MacPill(label, color: color),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: load.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: mac.fill2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            level == 'over'
                ? 'ستاسو کمپیوټر لپاره $recommended کړکۍ ښې دي — له دې زیاتې یې '
                    'ورو کوي.'
                : 'ستاسو کمپیوټر تر $recommended کړکیو پورې اسانه چلوي.',
            style: TextStyle(fontSize: 11.5, color: mac.text2, height: 1.5),
          ),
          if (accountsHint(estimate) != null) ...[
            const SizedBox(height: 3),
            Text(
              accountsHint(estimate)!,
              style: TextStyle(fontSize: 11.5, color: mac.text3),
            ),
          ],
        ],
      ),
    );
  }

  String? accountsHint(Map<String, dynamic> estimate) {
    final machine = estimate['machine'] as Map<String, dynamic>?;
    if (machine == null || machine['measured'] != true) {
      return 'دا یو اټکل دی — د حافظې ریښتینې اندازه نه شوه لوستل کېدای.';
    }
    return null;
  }
}

/// One of the quick answers, drawn as a little picture of the screen split.
class _LaneOption extends StatelessWidget {
  const _LaneOption({
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final ink = selected ? mac.accent : mac.text2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? mac.accentSoft : mac.fill,
            borderRadius: BorderRadius.circular(MacRadius.control),
            border: Border.all(
              color: selected ? mac.accent : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 26,
                height: 17,
                child: CustomPaint(painter: _TilePainter(count, ink)),
              ),
              const SizedBox(height: 5),
              Text('$count',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TilePainter extends CustomPainter {
  const _TilePainter(this.count, this.color);

  final int count;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fill = Paint()..color = color.withValues(alpha: 0.18);

    void cell(double x, double y, double w, double h) {
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h), const Radius.circular(1.5));
      canvas.drawRRect(rect, fill);
      canvas.drawRRect(rect, stroke);
    }

    final w = size.width;
    final h = size.height;
    switch (count) {
      case 1:
        cell(0.5, 0.5, w - 1, h - 1);
        break;
      case 2:
        cell(0.5, 0.5, w / 2 - 1.5, h - 1);
        cell(w / 2 + 1, 0.5, w / 2 - 1.5, h - 1);
        break;
      default:
        final cw = w / 2 - 1.5;
        final ch = h / 2 - 1.5;
        cell(0.5, 0.5, cw, ch);
        cell(w / 2 + 1, 0.5, cw, ch);
        cell(0.5, h / 2 + 1, cw, ch);
        if (count > 3) cell(w / 2 + 1, h / 2 + 1, cw, ch);
    }
  }

  @override
  bool shouldRepaint(_TilePainter old) =>
      old.count != count || old.color != color;
}

/// This task's own log — separate from the app-wide event stream, so a task
/// that ran last week can still be read back.
Future<void> showTaskLog(BuildContext context, WebTask task) async {
  final state = context.read<AppState>();
  await showMacSheet<void>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: _TaskLogSheet(task: task),
    ),
  );
}

class _TaskLogSheet extends StatefulWidget {
  const _TaskLogSheet({required this.task});

  final WebTask task;

  @override
  State<_TaskLogSheet> createState() => _TaskLogSheetState();
}

class _TaskLogSheetState extends State<_TaskLogSheet> {
  List<Map<String, dynamic>>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await context.read<AppState>().taskLog(widget.task.id);
    if (mounted) setState(() => _entries = entries);
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final entries = _entries;

    return MacSheet(
      title: 'د کار لاګ',
      subtitle: widget.task.name,
      icon: Icons.article_outlined,
      width: 640,
      body: SizedBox(
        height: 380,
        child: entries == null
            ? Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: mac.accent),
                ),
              )
            : entries.isEmpty
                ? Center(
                    child: Text(
                      'دا کار لا نه دی چلېدلی — لاګ یې تش دی.',
                      style: TextStyle(fontSize: 13, color: mac.text2),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: entries.length,
                      itemBuilder: (context, index) =>
                          _LogLine(entry: entries[index]),
                    ),
                  ),
      ),
      actions: [
        MacButton(
          label: 'بندول',
          large: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 10),
        MacButton(
          label: 'لاګ پاک کړه',
          icon: Icons.clear_all_rounded,
          large: true,
          onPressed: entries == null || entries.isEmpty
              ? null
              : () async {
                  await context.read<AppState>().clearTaskLog(widget.task.id);
                  await _load();
                },
        ),
      ],
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final level = entry['level'] as String? ?? 'info';
    final color = switch (level) {
      'error' => mac.red,
      'warn' => mac.orange,
      _ => mac.text2,
    };
    final ts = (entry['ts'] as num?)?.toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${entry['message'] ?? ''}',
              style: TextStyle(fontSize: 12, color: color, height: 1.45),
            ),
          ),
          if (ts != null) ...[
            const SizedBox(width: 10),
            Text(
              _clock(ts),
              style: TextStyle(fontSize: 11, color: mac.text3),
            ),
          ],
        ],
      ),
    );
  }

  static String _clock(int epochMs) {
    final when = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    final ss = when.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}
