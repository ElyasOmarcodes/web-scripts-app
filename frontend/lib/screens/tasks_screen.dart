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

enum _Filter { all, done, failed, partial }

/// The work list: every task the user built, with its colour and its controls.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tasks = _apply(state.tasks.tasks);

    return PageBody(
      header: PageHeader(
        title: 'کارونه',
        subtitle: state.tasks.total == 0
            ? 'یو سکریپټ + اکاونټونه = یو کار چې هر وخت یې چلولی شئ'
            : '${state.tasks.total} کارونه · '
                '${state.tasks.overview['done'] ?? 0} بشپړ · '
                '${state.tasks.overview['partial'] ?? 0} نیمګړي',
        actions: [
          MacSegmented<_Filter>(
            value: _filter,
            items: const {
              _Filter.all: 'ټول',
              _Filter.done: 'بشپړ',
              _Filter.partial: 'نیمګړي',
              _Filter.failed: 'ناکام',
            },
            onChanged: (value) => setState(() => _filter = value),
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
      child: tasks.isEmpty
          ? _Empty(hasAny: state.tasks.total > 0)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final task in tasks) ...[
                  TaskCard(task: task, state: state),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  List<WebTask> _apply(List<WebTask> tasks) {
    switch (_filter) {
      case _Filter.all:
        return tasks;
      case _Filter.done:
        return tasks.where((t) => t.status == 'done').toList();
      case _Filter.failed:
        return tasks.where((t) => t.status == 'failed').toList();
      case _Filter.partial:
        return tasks.where((t) => t.status == 'partial').toList();
    }
  }
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
Widget taskIcon(String status, Color color) {
  switch (status) {
    case 'done':
      return Icon(Icons.check_circle, size: 18, color: color);
    case 'failed':
      return Icon(Icons.error, size: 18, color: color);
    case 'partial':
      return Icon(Icons.pause_circle_filled, size: 18, color: color);
    case 'running':
      return Icon(Icons.autorenew, size: 18, color: color);
    default:
      return Icon(Icons.radio_button_unchecked, size: 18, color: color);
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
    final look = taskLook(mac, running ? 'running' : task.status);
    final script =
        state.scripts.where((s) => s.id == task.scriptId).firstOrNull;

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                // The status stripe: the first thing the eye lands on.
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: look.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child:
                        taskIcon(running ? 'running' : task.status, look.color),
                  ),
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
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          script?.name ?? 'سکریپټ نه دی ټاکل شوی',
                          '${task.accountIds.length} اکاونټه',
                          'په یو وخت کې ${task.concurrency}',
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
          Container(height: 0.8, color: mac.hairline),
          _AccountStrip(task: task, state: state),
        ],
      ),
    );
  }
}

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
      return MacButton(
        label: 'ودروه',
        icon: Icons.stop_rounded,
        style: MacButtonStyle.danger,
        onPressed: state.stopSession,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.canResume) ...[
          MacButton(
            label: 'دوام ورکړه',
            icon: Icons.play_circle_outline_rounded,
            style: MacButtonStyle.primary,
            onPressed:
                state.busy ? null : () => state.runTask(task.id, resume: true),
          ),
          const SizedBox(width: 8),
        ],
        MacButton(
          label: task.canResume ? 'له سره' : 'چلول',
          icon: Icons.play_arrow_rounded,
          style:
              task.canResume ? MacButtonStyle.normal : MacButtonStyle.primary,
          onPressed: state.busy || task.accountIds.isEmpty
              ? null
              : () => state.runTask(task.id),
        ),
        const SizedBox(width: 4),
        MacIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'تنظیمات',
          onPressed:
              state.busy ? null : () => taskEditorFlow(context, task: task),
        ),
        MacIconButton(
          icon: Icons.delete_outline_rounded,
          tooltip: 'ړنګول',
          onPressed: state.busy ? null : () => _delete(context),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirmSheet(
      context,
      title: 'دا کار ړنګ شي؟',
      message: '«${task.name}» ړنګېږي. سکریپټ او اکاونټونه پرځای پاتې کېږي.',
      confirmLabel: 'ړنګ یې کړه',
    );
    if (ok && context.mounted) {
      await context.read<AppState>().deleteTask(task.id);
    }
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
            Text(
              '$label$steps',
              style: TextStyle(fontSize: 12, color: mac.text),
            ),
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
