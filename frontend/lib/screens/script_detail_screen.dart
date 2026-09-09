import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/script.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/account_dialogs.dart';
import '../widgets/dialogs.dart';
import '../widgets/log_panel.dart';
import '../widgets/mac_widgets.dart';
import 'dashboard_screen.dart' show relativeTime;
import 'shell.dart';

class ScriptDetailScreen extends StatefulWidget {
  const ScriptDetailScreen({super.key});

  @override
  State<ScriptDetailScreen> createState() => _ScriptDetailScreenState();
}

class _ScriptDetailScreenState extends State<ScriptDetailScreen> {
  double? _speed;
  bool? _headless;
  bool? _keepOpen;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final mac = MacPalette.of(context);
    final script = state.selected;

    if (script == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Options default to the saved settings until the user overrides them here.
    final speed = _speed ?? state.settings.speed;
    final headless = _headless ?? state.settings.headless;
    final keepOpen = _keepOpen ?? state.settings.keepOpen;
    final running = state.session == SessionState.playing &&
        state.activeScriptId == script.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  leading: MacIconButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'بېرته',
                    size: 20,
                    onPressed: state.closeScript,
                  ),
                  title: script.name,
                  subtitle: '${script.steps.length} ګامه'
                      '${script.startUrl.isEmpty ? '' : ' · ${script.startUrl.replaceFirst(RegExp(r'^https?://'), '')}'}'
                      ' · ${relativeTime(script.lastRunAt)}',
                  actions: [
                    MacButton(
                      label: 'نوم بدلول',
                      icon: Icons.edit_outlined,
                      onPressed: () => _rename(context, state, script),
                    ),
                    const SizedBox(width: 9),
                    if (running)
                      MacButton(
                        label: 'ودروه',
                        icon: Icons.stop_rounded,
                        style: MacButtonStyle.danger,
                        onPressed: state.stopSession,
                      )
                    else
                      MacButton(
                        label: 'چلول',
                        icon: Icons.play_arrow_rounded,
                        style: MacButtonStyle.primary,
                        onPressed: state.busy || script.steps.isEmpty
                            ? null
                            : () => _run(context, state, script,
                                speed: speed, headless: headless, keepOpen: keepOpen),
                      ),
                  ],
                ),
                _RunBar(
                  state: state,
                  speed: speed,
                  headless: headless,
                  keepOpen: keepOpen,
                  onSpeed: (value) => setState(() => _speed = value),
                  onHeadless: (value) => setState(() => _headless = value),
                  onKeepOpen: (value) => setState(() => _keepOpen = value),
                ),
                const SizedBox(height: 14),
                if (script.steps.isEmpty)
                  _NoSteps(script: script)
                else
                  MacCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            border: Border(
                                bottom: BorderSide(color: mac.hairline, width: 0.8)),
                          ),
                          child: Row(
                            children: [
                              Text('ګامونه',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: mac.text)),
                              const Spacer(),
                              Text(
                                '${script.steps.where((s) => s.enabled).length} فعال '
                                'له ${script.steps.length} څخه',
                                style: TextStyle(fontSize: 11.5, color: mac.text2),
                              ),
                            ],
                          ),
                        ),
                        _StepList(state: state, script: script),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const LogPanel(height: 150),
      ],
    );
  }

  Future<void> _rename(
      BuildContext context, AppState state, WebScript script) async {
    final name = await promptText(
      context,
      title: 'نوم بدلول',
      initialValue: script.name,
      label: 'نوم',
    );
    if (name != null && name.trim().isNotEmpty) {
      await state.renameScript(script.id, name.trim());
    }
  }

  Future<void> _run(
    BuildContext context,
    AppState state,
    WebScript script, {
    required double speed,
    required bool headless,
    required bool keepOpen,
  }) async {
    final account = await resolveRunAccount(context, script);
    if (!account.go) return;
    if (!context.mounted) return;

    final variables = await collectVariables(context, script);
    if (variables == null) return;

    await state.runScript(
      script.id,
      variables: variables,
      speed: speed,
      headless: headless,
      keepOpen: keepOpen,
      accountId: account.accountId,
    );
  }
}

class _RunBar extends StatelessWidget {
  const _RunBar({
    required this.state,
    required this.speed,
    required this.headless,
    required this.keepOpen,
    required this.onSpeed,
    required this.onHeadless,
    required this.onKeepOpen,
  });

  final AppState state;
  final double speed;
  final bool headless;
  final bool keepOpen;
  final ValueChanged<double> onSpeed;
  final ValueChanged<bool> onHeadless;
  final ValueChanged<bool> onKeepOpen;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final running = state.session == SessionState.playing;
    final total = state.totalSteps ?? 0;

    return MacCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Text('چټکتیا', style: TextStyle(fontSize: 12.5, color: mac.text2)),
          const SizedBox(width: 8),
          MacSlider(
            value: speed,
            min: 0.5,
            max: 4,
            divisions: 7,
            width: 120,
            onChanged: state.busy ? null : onSpeed,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 36,
            child: Text('${speed.toStringAsFixed(1)}×',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: mac.text)),
          ),
          const SizedBox(width: 18),
          MacSwitch(value: headless, onChanged: state.busy ? null : onHeadless),
          const SizedBox(width: 8),
          Text('پټ چلول', style: TextStyle(fontSize: 12.5, color: mac.text)),
          const SizedBox(width: 18),
          MacSwitch(value: keepOpen, onChanged: state.busy ? null : onKeepOpen),
          const SizedBox(width: 8),
          Text('براوزر پرانیستی پرېږده',
              style: TextStyle(fontSize: 12.5, color: mac.text)),
          const Spacer(),
          if (running && total > 0) ...[
            MacPill('${state.currentStep ?? 0} / $total ګامه',
                color: mac.accent, background: mac.accentSoft),
            const SizedBox(width: 10),
            SizedBox(
              width: 130,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: (state.currentStep ?? 0) / total,
                  minHeight: 4,
                  backgroundColor: mac.fill2,
                  valueColor: AlwaysStoppedAnimation(mac.accent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.state, required this.script});

  final AppState state;
  final WebScript script;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        buildDefaultDragHandles: false,
        itemCount: script.steps.length,
        onReorder: (oldIndex, newIndex) {
          if (!state.busy) state.reorderSteps(oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          final step = script.steps[index];
          return StepTile(
            key: ValueKey(step.id),
            index: index,
            step: step,
            state: state,
            active: state.session == SessionState.playing &&
                state.currentStep == index + 1,
            done: state.session == SessionState.playing &&
                (state.currentStep ?? 0) > index + 1,
          );
        },
      ),
    );
  }
}

class StepTile extends StatefulWidget {
  const StepTile({
    super.key,
    required this.index,
    required this.step,
    required this.state,
    this.active = false,
    this.done = false,
    this.readOnly = false,
  });

  final int index;
  final StepModel step;
  final AppState state;
  final bool active;
  final bool done;
  final bool readOnly;

  @override
  State<StepTile> createState() => _StepTileState();
}

class _StepTileState extends State<StepTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final step = widget.step;
    final locator = step.targets.isEmpty ? '' : step.targets.first.value;

    Color numberBg = mac.fill2;
    Color numberFg = mac.text2;
    if (widget.active) {
      numberBg = mac.accent;
      numberFg = Colors.white;
    } else if (widget.done) {
      numberBg = mac.green.withValues(alpha: 0.2);
      numberFg = mac.green;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: widget.active
              ? mac.accentSoft
              : (_hover ? mac.fill : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Opacity(
          opacity: step.enabled ? 1 : 0.45,
          child: Row(
            children: [
              if (!widget.readOnly)
                ReorderableDragStartListener(
                  index: widget.index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Icon(Icons.drag_indicator, size: 16, color: mac.text3),
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                width: 21,
                height: 21,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: numberBg, shape: BoxShape.circle),
                child: Text('${widget.index + 1}',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, color: numberFg)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(step.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: mac.text)),
                    if (locator.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          locator,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            color: mac.text3,
                            fontFamily: 'Consolas',
                            fontFamilyFallback: const ['Menlo', 'monospace'],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (step.framePath.isNotEmpty) ...[
                MacPill('iframe ${step.framePath.join('/')}'),
                const SizedBox(width: 8),
              ],
              if (step.delayMs > 0) ...[
                // A latin measurement keeps its own direction inside the RTL row.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('${step.delayMs} ms',
                      style: TextStyle(fontSize: 11, color: mac.text3)),
                ),
                const SizedBox(width: 8),
              ],
              if (!widget.readOnly)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: _hover ? 1 : 0.35,
                  child: Row(
                    children: [
                      if (step.isEditable && !step.secret)
                        MacIconButton(
                          icon: Icons.edit_outlined,
                          tooltip: 'ارزښت بدلول',
                          onPressed: widget.state.busy ? null : () => _edit(context),
                        ),
                      MacIconButton(
                        icon: step.enabled
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        tooltip: step.enabled ? 'غیر فعالول' : 'فعالول',
                        onPressed: widget.state.busy
                            ? null
                            : () => widget.state.toggleStep(step),
                      ),
                      MacIconButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'ړنګول',
                        onPressed:
                            widget.state.busy ? null : () => _delete(context),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final step = widget.step;
    final isGoto = step.action == 'goto';
    final value = await promptText(
      context,
      title: 'ارزښت بدلول',
      initialValue: isGoto ? (step.url ?? '') : (step.value ?? ''),
      label: isGoto ? 'پته' : 'متن',
    );
    if (value == null) return;
    if (isGoto) {
      await widget.state.editStep(step, url: value);
    } else {
      await widget.state.editStep(step, value: value);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = !widget.state.settings.confirmDelete ||
        await confirmSheet(
          context,
          title: 'ګام ړنګول',
          message: '«${widget.step.description}» ړنګ کړم؟',
          confirmLabel: 'ړنګ کړه',
        );
    if (ok) await widget.state.deleteStep(widget.step);
  }
}

class _NoSteps extends StatelessWidget {
  const _NoSteps({required this.script});

  final WebScript script;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return MacCard(
      padding: const EdgeInsets.symmetric(vertical: 46, horizontal: 20),
      child: Column(
        children: [
          Icon(Icons.list_alt_outlined, size: 30, color: mac.text3),
          const SizedBox(height: 12),
          Text('دې سکریپټ کې ګامونه نشته',
              style: TextStyle(fontSize: 13, color: mac.text2)),
          const SizedBox(height: 6),
          Text('د «ثبتول» تڼۍ ووهئ او خپله لار وښایاست.',
              style: TextStyle(fontSize: 12, color: mac.text3)),
          const SizedBox(height: 16),
          MacButton(
            label: 'ثبتول پیل کړه',
            icon: Icons.fiber_manual_record,
            style: MacButtonStyle.primary,
            onPressed: () => startRecordingFlow(context),
          ),
        ],
      ),
    );
  }
}
