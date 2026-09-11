import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/mac_widgets.dart';
import '../widgets/task_dialogs.dart';
import 'dashboard_screen.dart' show relativeTime;
import 'shell.dart';

/// The five states a task can be in, as the list filters them.
enum TaskFilter { all, running, done, partial, failed }

const _filterLabels = <TaskFilter, String>{
  TaskFilter.all: 'ټول',
  TaskFilter.running: 'روان',
  TaskFilter.done: 'بشپړ',
  TaskFilter.partial: 'نیمګړي',
  TaskFilter.failed: 'ناکام',
};

/// The work list: every task the user built, with its colour and its controls.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  TaskFilter _filter = TaskFilter.all;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tasks = _apply(state.tasks.tasks, state);
    final counts = _counts(state);

    return PageBody(
      header: PageHeader(
        title: 'کارونه',
        subtitle: state.tasks.total == 0
            ? 'یو سکریپټ + اکاونټونه = یو کار چې هر وخت یې چلولی شئ'
            : '${state.tasks.total} کارونه',
        actions: [
          SizedBox(
            width: 190,
            child: MacField(
              controller: _search,
              hint: 'د کار یا سکریپټ لټون…',
              prefix: Icon(Icons.search_rounded,
                  size: 14, color: MacPalette.of(context).text3),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          MacButton(
            label: 'نوی کار',
            icon: Icons.add_rounded,
            style: MacButtonStyle.primary,
            onPressed: () => taskEditorFlow(context),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The filter bar sits with the list, not in the toolbar: it counts
          // what it filters, which is only true once the list is loaded.
          _FilterBar(
            value: _filter,
            counts: counts,
            onChanged: (value) => setState(() => _filter = value),
          ),
          const SizedBox(height: 14),
          if (tasks.isEmpty)
            _Empty(hasAny: state.tasks.total > 0)
          else
            for (final task in tasks) ...[
              TaskCard(task: task, state: state),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Map<TaskFilter, int> _counts(AppState state) {
    final counts = {for (final f in TaskFilter.values) f: 0};
    counts[TaskFilter.all] = state.tasks.tasks.length;
    for (final task in state.tasks.tasks) {
      final status = state.activeTaskId == task.id ? 'running' : task.status;
      final filter = switch (status) {
        'running' => TaskFilter.running,
        'done' => TaskFilter.done,
        'partial' => TaskFilter.partial,
        'failed' => TaskFilter.failed,
        _ => null,
      };
      if (filter != null) counts[filter] = counts[filter]! + 1;
    }
    return counts;
  }

  List<WebTask> _apply(List<WebTask> tasks, AppState state) {
    final needle = _search.text.trim().toLowerCase();
    return tasks.where((task) {
      final status = state.activeTaskId == task.id ? 'running' : task.status;
      final passesFilter = switch (_filter) {
        TaskFilter.all => true,
        TaskFilter.running => status == 'running',
        TaskFilter.done => status == 'done',
        TaskFilter.partial => status == 'partial',
        TaskFilter.failed => status == 'failed',
      };
      if (!passesFilter) return false;
      if (needle.isEmpty) return true;
      final script = state.scripts
          .where((s) => s.id == task.scriptId)
          .map((s) => s.name)
          .join();
      return task.name.toLowerCase().contains(needle) ||
          script.toLowerCase().contains(needle);
    }).toList();
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.value,
    required this.counts,
    required this.onChanged,
  });

  final TaskFilter value;
  final Map<TaskFilter, int> counts;
  final ValueChanged<TaskFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Row(
      children: [
        for (final filter in TaskFilter.values) ...[
          StatusChip(
            label: _filterLabels[filter]!,
            count: counts[filter] ?? 0,
            color: _filterColor(mac, filter),
            selected: value == filter,
            onTap: () => onChanged(filter),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  Color _filterColor(MacPalette mac, TaskFilter filter) => switch (filter) {
        TaskFilter.running => mac.accent,
        TaskFilter.done => mac.green,
        TaskFilter.partial => mac.orange,
        TaskFilter.failed => mac.red,
        TaskFilter.all => mac.text2,
      };
}

/// Colour and wording for a task's state — green done, red failed, yellow
/// stopped half way.
({Color color, String label}) taskLook(MacPalette mac, String status) {
  switch (status) {
    case 'done':
      return (color: mac.green, label: 'بشپړ شو');
    case 'failed':
      return (color: mac.red, label: 'ناکام');
    case 'partial':
      return (color: mac.orange, label: 'نیمایي کې پاتې');
    case 'running':
      return (color: mac.accent, label: 'روان دی');
    default:
      return (color: mac.text3, label: 'لا نه دی چلېدلی');
  }
}

/// The icon is chosen here rather than handed back with the colour above:
/// Flutter's icon tree-shaker only keeps glyphs it can see used directly, and
/// icons passed around inside records were dropped from the font.
Widget taskIcon(String status, Color color, {double size = 18}) {
  switch (status) {
    case 'done':
      return Icon(Icons.check_circle, size: size, color: color);
    case 'failed':
      return Icon(Icons.error, size: size, color: color);
    case 'partial':
      return Icon(Icons.pause_circle_filled, size: size, color: color);
    case 'running':
      return Icon(Icons.autorenew, size: size, color: color);
    default:
      return Icon(Icons.radio_button_unchecked, size: size, color: color);
  }
}

class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.state});

  final WebTask task;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final running = state.activeTaskId == task.id;
    final status = running ? 'running' : task.status;
    final look = taskLook(mac, status);
    final script =
        state.scripts.where((s) => s.id == task.scriptId).map((s) => s.name);

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: look.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: taskIcon(status, look.color)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              task.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: mac.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          MacPill(look.label, color: look.color),
                          if (task.runsHidden) ...[
                            const SizedBox(width: 6),
                            MacPill('پټ', color: mac.text3),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          script.isEmpty
                              ? 'سکریپټ نه دی ټاکل شوی'
                              : script.first,
                          '${task.accountIds.length} اکاونټه',
                          '${task.concurrency} کړکۍ',
                          if (task.lastRunAt != null)
                            relativeTime(task.lastRunAt),
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: mac.text2),
                      ),
                    ],
                  ),
                ),
                _Controls(task: task, state: state, running: running),
              ],
            ),
          ),
          if (running) _Progress(task: task, state: state),
          Container(height: 0.8, color: mac.hairline),
          _AccountStrip(task: task, state: state),
        ],
      ),
    );
  }
}

/// One primary button, and everything else behind a single menu — the row of
/// five buttons per card was noise.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.task,
    required this.state,
    required this.running,
  });

  final WebTask task;
  final AppState state;
  final bool running;

  @override
  Widget build(BuildContext context) {
    if (running) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MacButton(
            label: 'ودروه',
            icon: Icons.stop_rounded,
            style: MacButtonStyle.danger,
            onPressed: state.stopSession,
          ),
          const SizedBox(width: 6),
          _Menu(task: task, state: state, running: true),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MacButton(
          label: task.canResume ? 'دوام ورکړه' : 'چلول',
          icon: task.canResume
              ? Icons.play_circle_outline_rounded
              : Icons.play_arrow_rounded,
          style: MacButtonStyle.primary,
          onPressed: state.busy || task.accountIds.isEmpty
              ? null
              : () => state.runTask(task.id, resume: task.canResume),
        ),
        const SizedBox(width: 6),
        _Menu(task: task, state: state, running: false),
      ],
    );
  }
}

/// The overflow menu: a macOS popover, not a row of icons.
class _Menu extends StatelessWidget {
  const _Menu({required this.task, required this.state, required this.running});

  final WebTask task;
  final AppState state;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return PopupMenuButton<String>(
      tooltip: 'نور',
      position: PopupMenuPosition.under,
      color: mac.window,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MacRadius.menu),
        side: BorderSide(color: mac.hairline, width: 0.8),
      ),
      // Drawn rather than fetched from the icon font: the tree-shaker keeps
      // dropping this one, and three dots are three dots.
      icon: SizedBox(
        width: 18,
        height: 18,
        child: CustomPaint(painter: _DotsPainter(mac.text2)),
      ),
      splashRadius: 16,
      itemBuilder: (context) => [
        _item('log', 'لاګ وګوره', Icons.article_outlined, mac),
        if (!running && task.canResume)
          _item('rerun', 'له سره وچلوه', Icons.replay_rounded, mac),
        if (!running) _item('edit', 'تنظیمات', Icons.tune_rounded, mac),
        if (!running)
          _item('delete', 'ړنګول', Icons.delete_outline_rounded, mac,
              color: mac.red),
      ],
      onSelected: (value) => _act(context, value),
    );
  }

  PopupMenuItem<String> _item(
    String value,
    String label,
    IconData icon,
    MacPalette mac, {
    Color? color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 34,
      child: Row(
        children: [
          Icon(icon, size: 15, color: color ?? mac.text2),
          const SizedBox(width: 9),
          Text(label, style: TextStyle(fontSize: 13, color: color ?? mac.text)),
        ],
      ),
    );
  }

  Future<void> _act(BuildContext context, String value) async {
    switch (value) {
      case 'log':
        await showTaskLog(context, task);
        break;
      case 'rerun':
        await state.runTask(task.id);
        break;
      case 'edit':
        await taskEditorFlow(context, task: task);
        break;
      case 'delete':
        final ok = await confirmSheet(
          context,
          title: 'دا کار ړنګ شي؟',
          message:
              '«${task.name}» ړنګېږي. سکریپټ او اکاونټونه پرځای پاتې کېږي.',
          confirmLabel: 'ړنګ یې کړه',
        );
        if (ok && context.mounted) {
          await context.read<AppState>().deleteTask(task.id);
        }
        break;
    }
  }
}

/// How far through the accounts a running task is.
class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final y = size.height / 2;
    for (final x in [size.width / 2 - 5, size.width / 2, size.width / 2 + 5]) {
      canvas.drawCircle(Offset(x, y), 1.6, paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

class _Progress extends StatelessWidget {
  const _Progress({required this.task, required this.state});

  final WebTask task;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final total = task.accountIds.length;
    final done = state.taskProgress.values.where((s) => s != 'running').length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: total == 0 ? null : done / total,
          minHeight: 4,
          backgroundColor: mac.fill2,
          valueColor: AlwaysStoppedAnimation<Color>(mac.accent),
        ),
      ),
    );
  }
}

/// One chip per account, coloured by how that account's turn went.
class _AccountStrip extends StatelessWidget {
  const _AccountStrip({required this.task, required this.state});

  final WebTask task;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    if (task.accountIds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Text(
          'هېڅ اکاونټ نه دی ټاکل شوی — «تنظیمات» کې یې زیات کړئ.',
          style: TextStyle(fontSize: 12, color: mac.text2),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final id in task.accountIds)
            _AccountChip(
              label: state.accounts.account(id)?.label ?? id,
              run: task.runFor(id),
              live: state.taskProgress[id],
            ),
        ],
      ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.label, this.run, this.live});

  final String label;
  final AccountRun? run;
  final String? live;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final status = live ?? run?.status ?? 'pending';
    final color = switch (status) {
      'ok' => mac.green,
      'failed' => mac.red,
      'running' => mac.accent,
      'stopped' => mac.orange,
      _ => mac.text3,
    };
    final steps =
        run != null && run!.total > 0 ? ' ${run!.completed}/${run!.total}' : '';

    return Tooltip(
      message: run?.error ?? label,
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(MacRadius.control),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chipIcon(status, color),
            const SizedBox(width: 6),
            Text('$label$steps',
                style: TextStyle(fontSize: 12, color: mac.text)),
          ],
        ),
      ),
    );
  }
}

Widget _chipIcon(String status, Color color) {
  switch (status) {
    case 'ok':
      return Icon(Icons.check_rounded, size: 13, color: color);
    case 'failed':
      return Icon(Icons.close_rounded, size: 13, color: color);
    case 'running':
      return Icon(Icons.autorenew_rounded, size: 13, color: color);
    case 'stopped':
      return Icon(Icons.pause_rounded, size: 13, color: color);
    default:
      return Icon(Icons.remove_rounded, size: 13, color: color);
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
        padding: const EdgeInsets.symmetric(vertical: 54, horizontal: 24),
        child: Column(
          children: [
            Icon(Icons.checklist_rounded, size: 30, color: mac.text3),
            const SizedBox(height: 12),
            Text(
              hasAny
                  ? 'په دې فلټر کې هېڅ کار نشته'
                  : 'لا هېڅ کار نه دی جوړ شوی',
              style: TextStyle(fontSize: 14, color: mac.text),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 460,
              child: Text(
                'یو کار دا دی: کوم سکریپټ، په کومو اکاونټونو، او په یو وخت کې '
                'څو کړکۍ. بیا یې یوازې چلوئ.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: mac.text2, height: 1.6),
              ),
            ),
            const SizedBox(height: 16),
            MacButton(
              label: 'نوی کار جوړ کړه',
              icon: Icons.add_rounded,
              style: MacButtonStyle.primary,
              large: true,
              onPressed: () => taskEditorFlow(context),
            ),
          ],
        ),
      ),
    );
  }
}
