import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/script.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/mac_widgets.dart';
import 'shell.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'ښه راغلاست',
            subtitle: 'ستاسو د اتومات کارونو لنډه کتنه',
            actions: [
              MacButton(
                label: 'نوی سکریپټ',
                icon: Icons.add_rounded,
                onPressed: () => newEmptyScriptFlow(context),
              ),
              const SizedBox(width: 9),
              MacButton(
                label: 'نوې لارښوونه',
                icon: Icons.fiber_manual_record,
                style: MacButtonStyle.primary,
                onPressed: state.busy ? null : () => startRecordingFlow(context),
              ),
            ],
          ),
          _StatRow(state: state),
          const SizedBox(height: 22),
          SizedBox(
            height: 300,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 135, child: _RecentPanel(state: state)),
                const SizedBox(width: 14),
                Expanded(flex: 100, child: _WeekPanel(state: state)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _QuickRow(state: state),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final minutes = state.minutesSaved;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            gradient: 'blue',
            icon: Icons.description_outlined,
            label: 'ټول سکریپټونه',
            value: '${state.scripts.length}',
            hint: '${state.totalStepCount} ګامه په ټوله کې',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            gradient: 'green',
            icon: Icons.check_rounded,
            label: 'بریالي چلونه',
            value: '${state.successCount}',
            hint: state.failedCount == 0
                ? 'هېڅ ناکامي نشته'
                : '${state.failedCount} ناکام',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            gradient: 'orange',
            icon: Icons.schedule_rounded,
            label: 'وخت خوندي شوی',
            value: minutes < 1
                ? '—'
                : (minutes >= 60
                    ? (minutes / 60).toStringAsFixed(1)
                    : minutes.round().toString()),
            hint: minutes < 1
                ? 'لا چلون نشته'
                : (minutes >= 60 ? 'ساعته' : 'دقیقې'),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StatCard(
            gradient: 'purple',
            icon: Icons.bolt_rounded,
            label: 'بریالیتوب',
            value: state.successRate == 0 ? '—' : '${state.successRate}%',
            hint: '${state.neverRunCount} لا نه دي چلول شوي',
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.gradient,
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
  });

  final String gradient;
  final IconData icon;
  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = MacPalette.gradients[gradient]!;
    return Container(
      height: 106,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MacRadius.card),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.first.withOpacity(0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // The soft highlight blob, same as the mockup.
          Positioned(
            left: -30,
            top: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: Colors.white.withOpacity(0.92)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.92),
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      hint,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentPanel extends StatelessWidget {
  const _RecentPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final recent = state.recentScripts;

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHead(
            title: 'وروستي سکریپټونه',
            trailing: GestureDetector(
              onTap: () => state.navigate(AppPage.scripts),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text('ټول وګوره',
                    style: TextStyle(fontSize: 12, color: mac.accent)),
              ),
            ),
          ),
          Expanded(
            child: recent.isEmpty
                ? Center(
                    child: Text('لا هېڅ سکریپټ نشته',
                        style: TextStyle(fontSize: 12.5, color: mac.text3)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(6),
                    itemCount: recent.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 0.8, thickness: 0.8, color: mac.hairline),
                    itemBuilder: (context, index) =>
                        _ScriptRow(script: recent[index], state: state),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScriptRow extends StatefulWidget {
  const _ScriptRow({required this.script, required this.state});

  final WebScript script;
  final AppState state;

  @override
  State<_ScriptRow> createState() => _ScriptRowState();
}

class _ScriptRowState extends State<_ScriptRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final script = widget.script;
    final color = mac.avatarFor(script.id);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.state.openScript(script.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: _hover ? mac.fill : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              ScriptAvatar(script: script, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(script.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500, color: mac.text)),
                    const SizedBox(height: 1),
                    Text(
                      '${script.stepCount} ګامه · ${relativeTime(script.updatedAt)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: mac.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RunStatePill(script: script),
              const SizedBox(width: 8),
              MacIconButton(
                icon: Icons.play_arrow_rounded,
                tooltip: 'چلول',
                size: 17,
                onPressed: widget.state.busy
                    ? null
                    : () => runScriptFlow(context, script),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekPanel extends StatelessWidget {
  const _WeekPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final buckets = _weeklyRuns(state.scripts);
    final peak = buckets.reduce((a, b) => a > b ? a : b);
    const days = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHead(title: 'د اونۍ چلونه'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < buckets.length; i++) ...[
                    if (i > 0) const SizedBox(width: 7),
                    Expanded(
                      child: TweenAnimationBuilder<double>(
                        duration: Duration(milliseconds: 420 + i * 45),
                        curve: Curves.easeOutCubic,
                        tween: Tween(
                          begin: 0,
                          end: peak == 0 ? 0.06 : (buckets[i] / peak).clamp(0.06, 1.0),
                        ),
                        builder: (context, factor, _) => FractionallySizedBox(
                          heightFactor: factor,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                                bottom: Radius.circular(2),
                              ),
                              gradient: buckets[i] == 0
                                  ? null
                                  : LinearGradient(
                                      colors: MacPalette.gradients['blue']!,
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                              color: buckets[i] == 0 ? mac.fill2 : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      days[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: mac.text3),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Runs per weekday, from each script's last run timestamp.
  List<int> _weeklyRuns(List<WebScript> scripts) {
    final buckets = List<int>.filled(7, 0);
    final now = DateTime.now();
    for (final script in scripts) {
      final at = script.lastRunAt;
      if (at == null) continue;
      final when = DateTime.fromMillisecondsSinceEpoch(at);
      final age = now.difference(when).inDays;
      if (age < 0 || age > 6) continue;
      buckets[when.weekday % 7] += 1;
    }
    return buckets;
  }
}

class _PanelHead extends StatelessWidget {
  const _PanelHead({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: mac.hairline, width: 0.8)),
      ),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: mac.text)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _QuickRow extends StatelessWidget {
  const _QuickRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final last = state.recentScripts.isEmpty ? null : state.recentScripts.first;

    return Row(
      children: [
        Expanded(
          child: _QuickCard(
            color: mac.accent,
            icon: Icons.fiber_manual_record,
            title: 'نوې لارښوونه ثبت کړه',
            hint: 'براوزر پرانیزه او خپله لار وښایه',
            onTap: state.busy ? null : () => startRecordingFlow(context),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _QuickCard(
            color: mac.green,
            icon: Icons.play_arrow_rounded,
            title: last == null ? 'لا سکریپټ نشته' : 'وروستی سکریپټ بیا وچلوه',
            hint: last == null
                ? 'لومړی یوه لارښوونه ثبت کړئ'
                : '«${last.name}» · ${last.stepCount} ګامه',
            onTap: (last == null || state.busy)
                ? null
                : () => runScriptFlow(context, last),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _QuickCard(
            color: mac.orange,
            icon: Icons.settings_outlined,
            title: 'براوزر بدل کړه',
            hint: 'اوس: ${state.activeBrowserName}',
            onTap: () => state.navigate(AppPage.settings),
          ),
        ),
      ],
    );
  }
}

class _QuickCard extends StatefulWidget {
  const _QuickCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.hint,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback? onTap;

  @override
  State<_QuickCard> createState() => _QuickCardState();
}

class _QuickCardState extends State<_QuickCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final enabled = widget.onTap != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: _hover && enabled ? mac.fill : mac.window,
            borderRadius: BorderRadius.circular(MacRadius.card),
            border: Border.all(color: mac.hairline, width: 0.8),
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, size: 17, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: mac.text)),
                      const SizedBox(height: 2),
                      Text(widget.hint,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: mac.text2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- shared bits

class ScriptAvatar extends StatelessWidget {
  const ScriptAvatar({
    super.key,
    required this.script,
    required this.color,
    this.size = 30,
  });

  final WebScript script;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = script.name.trim().isEmpty ? '؟' : script.name.trim()[0];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 3.6),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.46,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class RunStatePill extends StatelessWidget {
  const RunStatePill({super.key, required this.script});

  final WebScript script;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    if (script.lastRunOk == null) {
      return const MacPill('لا نه دی چلول شوی');
    }
    return script.lastRunOk!
        ? MacPill('بریالی', color: mac.green, background: mac.green.withOpacity(0.16))
        : MacPill('ناکام', color: mac.red, background: mac.red.withOpacity(0.14));
  }
}

String relativeTime(int? epochMs) {
  if (epochMs == null || epochMs == 0) return 'لا نه دی چلول شوی';
  final when = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'همدا اوس';
  if (diff.inMinutes < 60) return '${diff.inMinutes} دقیقې مخکې';
  if (diff.inHours < 24) return '${diff.inHours} ساعته مخکې';
  if (diff.inDays == 1) return 'پرون';
  if (diff.inDays < 30) return '${diff.inDays} ورځې مخکې';
  return '${when.year}/${when.month}/${when.day}';
}
