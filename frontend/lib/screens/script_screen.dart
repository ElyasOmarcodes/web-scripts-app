import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/script.dart';
import '../state/app_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/log_panel.dart';

/// Detail view: inspect, edit and run a single recorded script.
class ScriptScreen extends StatefulWidget {
  const ScriptScreen({super.key});

  @override
  State<ScriptScreen> createState() => _ScriptScreenState();
}

class _ScriptScreenState extends State<ScriptScreen> {
  double _speed = 1.0;
  bool _headless = false;
  bool _keepOpen = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final script = state.selected;

    if (script == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(script.name),
        actions: [
          IconButton(
            tooltip: 'نوم بدلول',
            onPressed: () => _rename(context, state, script),
            icon: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _RunBar(
            state: state,
            script: script,
            speed: _speed,
            headless: _headless,
            keepOpen: _keepOpen,
            onSpeed: (value) => setState(() => _speed = value),
            onHeadless: (value) => setState(() => _headless = value),
            onKeepOpen: (value) => setState(() => _keepOpen = value),
          ),
          Expanded(
            child: script.steps.isEmpty
                ? const Center(child: Text('دې سکریپټ کې ګامونه نشته'))
                : _StepList(state: state, script: script),
          ),
          const LogPanel(height: 160),
        ],
      ),
    );
  }

  Future<void> _rename(
      BuildContext context, AppState state, WebScript script) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'نوم بدلول',
        initialValue: script.name,
        label: 'نوم',
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await state.renameScript(script.id, name.trim());
    }
  }
}

class _RunBar extends StatelessWidget {
  const _RunBar({
    required this.state,
    required this.script,
    required this.speed,
    required this.headless,
    required this.keepOpen,
    required this.onSpeed,
    required this.onHeadless,
    required this.onKeepOpen,
  });

  final AppState state;
  final WebScript script;
  final double speed;
  final bool headless;
  final bool keepOpen;
  final ValueChanged<double> onSpeed;
  final ValueChanged<bool> onHeadless;
  final ValueChanged<bool> onKeepOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = state.session == SessionState.playing;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
        border:
            Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: state.busy ? null : () => _run(context),
                icon: const Icon(Icons.play_arrow),
                label: const Text('چلول'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: running ? state.stopSession : null,
                icon: const Icon(Icons.stop),
                label: const Text('ودروه'),
              ),
              const SizedBox(width: 20),
              Text('چټکتیا: ${speed.toStringAsFixed(1)}×'),
              SizedBox(
                width: 180,
                child: Slider(
                  value: speed,
                  min: 0.5,
                  max: 4,
                  divisions: 7,
                  onChanged: state.busy ? null : onSpeed,
                ),
              ),
            ],
          ),
          if (running && state.totalSteps != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (state.currentStep ?? 0) / (state.totalSteps ?? 1),
            ),
          ],
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            children: [
              _Toggle(
                label: 'پټ چلول (headless)',
                value: headless,
                onChanged: state.busy ? null : onHeadless,
              ),
              _Toggle(
                label: 'براوزر پرانیستی پرېږده',
                value: keepOpen,
                onChanged: state.busy ? null : onKeepOpen,
              ),
              if (script.startUrl.isNotEmpty)
                Text(script.startUrl, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context) async {
    Map<String, String> variables = const {};
    if (script.variables.isNotEmpty) {
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => VariablesDialog(variables: script.variables),
      );
      if (result == null) return;
      variables = result;
    }
    await state.runScript(
      script.id,
      variables: variables,
      speed: speed,
      headless: headless,
      keepOpen: keepOpen,
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(value: value, onChanged: onChanged),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.state, required this.script});

  final AppState state;
  final WebScript script;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: script.steps.length,
      onReorder: (oldIndex, newIndex) {
        if (!state.busy) state.reorderSteps(oldIndex, newIndex);
      },
      buildDefaultDragHandles: !state.busy,
      itemBuilder: (context, index) {
        final step = script.steps[index];
        return _StepTile(
          key: ValueKey(step.id),
          index: index,
          step: step,
          state: state,
          running: state.session == SessionState.playing &&
              state.currentStep == index + 1,
        );
      },
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    super.key,
    required this.index,
    required this.step,
    required this.state,
    required this.running,
  });

  final int index;
  final StepModel step;
  final AppState state;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locator = step.targets.isEmpty ? '' : step.targets.first.value;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: running ? theme.colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Opacity(
        opacity: step.enabled ? 1 : 0.45,
        child: ListTile(
          leading: CircleAvatar(
            radius: 14,
            child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
          ),
          title: Text(step.description),
          subtitle: Text(
            locator.isEmpty
                ? '${step.action} • ${step.delayMs} ms'
                : '$locator • ${step.delayMs} ms'
                    '${step.framePath.isEmpty ? '' : ' • iframe ${step.framePath.join('/')}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (step.isEditable && !step.secret)
                IconButton(
                  tooltip: 'ارزښت بدلول',
                  onPressed: state.busy ? null : () => _edit(context),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              IconButton(
                tooltip: step.enabled ? 'غیر فعالول' : 'فعالول',
                onPressed: state.busy ? null : () => state.toggleStep(step),
                icon: Icon(
                  step.enabled ? Icons.visibility : Icons.visibility_off,
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: 'ړنګول',
                onPressed: state.busy ? null : () => _delete(context),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: 'ارزښت بدلول',
        initialValue: step.action == 'goto' ? (step.url ?? '') : (step.value ?? ''),
        label: step.action == 'goto' ? 'پته' : 'متن',
      ),
    );
    if (value == null) return;
    if (step.action == 'goto') {
      await state.editStep(step, url: value);
    } else {
      await state.editStep(step, value: value);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'ګام ړنګول',
      message: '«${step.description}» ړنګ کړم؟',
      confirmLabel: 'ړنګ کړه',
    );
    if (ok) await state.deleteStep(step);
  }
}
