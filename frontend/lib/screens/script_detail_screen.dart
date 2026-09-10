import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/script.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/script_dialogs.dart';
import '../widgets/task_dialogs.dart';
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
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final mac = MacPalette.of(context);
    final script = state.selected;

    if (script == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: PageBody(
            header: PageHeader(
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
                MacButton(
                  label: 'تنظیمات',
                  icon: Icons.tune_rounded,
                  onPressed: () => scriptSettingsFlow(context, script),
                ),
                const SizedBox(width: 9),
                MacButton(
                  label: 'کار جوړ کړه',
                  icon: Icons.checklist_rounded,
                  style: MacButtonStyle.primary,
                  onPressed: state.busy || script.steps.isEmpty
                      ? null
                      : () => taskEditorFlow(context, scriptId: script.id),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                                bottom: BorderSide(
                                    color: mac.hairline, width: 0.8)),
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
                                style:
                                    TextStyle(fontSize: 11.5, color: mac.text2),
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
                    child:
                        Icon(Icons.drag_indicator, size: 16, color: mac.text3),
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                width: 21,
                height: 21,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(color: numberBg, shape: BoxShape.circle),
                child: Text('${widget.index + 1}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: numberFg)),
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
                          onPressed:
                              widget.state.busy ? null : () => _edit(context),
                        ),
                      MacIconButton(
                        icon: step.optional
                            ? Icons.help_outline_rounded
                            : Icons.priority_high_rounded,
                        tooltip: step.optional
                            ? 'اختیاري: که ونه موندل شو، پرېښودل کېږي'
                            : 'اړین: باید ومومل شي',
                        onPressed: widget.state.busy
                            ? null
                            : () => widget.state.toggleOptional(step),
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
