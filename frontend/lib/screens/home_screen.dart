import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/script.dart';
import '../state/app_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/log_panel.dart';
import 'script_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _showErrors(context, state);

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebScripts — د ویب کارونه اتومات کړئ'),
        actions: [
          const _SessionChip(),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'تازه کول',
            onPressed: state.connected ? state.refresh : null,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: state.connected
          ? _RecordButton(state: state)
          : null,
      body: Column(
        children: [
          Expanded(child: _Body(state: state)),
          const LogPanel(),
        ],
      ),
    );
  }

  void _showErrors(BuildContext context, AppState state) {
    final error = state.consumeError();
    if (error == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    });
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.booting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('د سرور سره نښلېدل…'),
          ],
        ),
      );
    }
    if (!state.connected) {
      return _Disconnected(state: state);
    }
    if (state.scripts.isEmpty) {
      return const _EmptyState();
    }
    return _ScriptList(state: state);
  }
}

class _Disconnected extends StatelessWidget {
  const _Disconnected({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('د Python سرور سره اړیکه ونه شوه',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              state.connectionError ?? '',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'لومړی scripts\\setup.ps1 وچلوئ، بیا دا برنامه بیا پیل کړئ.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.retryConnection,
              icon: const Icon(Icons.refresh),
              label: const Text('بیا هڅه'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('لا هېڅ سکریپټ نشته', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const SizedBox(
              width: 520,
              child: Text(
                'د «نوې لارښوونه» تڼۍ ووهئ، براوزر به پرانیستل شي. '
                'هر کلیک او هر څه چې لیکئ ثبتېږي. کله چې ودرېږئ، سکریپټ خوندي کېږي '
                'او بیا یې هر وخت په یوه کلیک چلولی شئ.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScriptList extends StatelessWidget {
  const _ScriptList({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: state.scripts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _ScriptCard(script: state.scripts[index], state: state),
    );
  }
}

class _ScriptCard extends StatelessWidget {
  const _ScriptCard({required this.script, required this.state});

  final WebScript script;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = state.activeScriptId == script.id &&
        state.session == SessionState.playing;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _StatusDot(ok: script.lastRunOk),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(script.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${script.stepCount} ګامه'
                      '${script.startUrl.isEmpty ? '' : ' • ${script.startUrl}'}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (running)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                tooltip: 'چلول',
                onPressed: state.busy ? null : () => _run(context),
                icon: const Icon(Icons.play_arrow),
              ),
              IconButton(
                tooltip: 'ړنګول',
                onPressed: state.busy ? null : () => _delete(context),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    await state.openScript(script.id);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ScriptScreen()),
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
    await state.runScript(script.id, variables: variables);
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'ړنګول',
      message: '«${script.name}» ړنګ کړم؟ دا کار بیرته نه کېږي.',
      confirmLabel: 'ړنګ کړه',
    );
    if (ok) await state.deleteScript(script.id);
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({this.ok});

  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final color = ok == null
        ? Theme.of(context).colorScheme.outline
        : (ok! ? Colors.green : Theme.of(context).colorScheme.error);
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SessionChip extends StatelessWidget {
  const _SessionChip();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    late final String label;
    late final Color color;

    switch (state.session) {
      case SessionState.recording:
        label = 'ثبتول (${state.recordedSteps})';
        color = Colors.red;
        break;
      case SessionState.playing:
        label = state.totalSteps == null
            ? 'روان دی'
            : 'روان دی ${state.currentStep ?? 0}/${state.totalSteps}';
        color = Colors.blue;
        break;
      case SessionState.idle:
        label = state.connected ? 'چمتو' : 'نه دی نښتی';
        color = state.connected ? Colors.green : Colors.grey;
        break;
    }

    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (state.session == SessionState.recording) {
      return FloatingActionButton.extended(
        backgroundColor: Theme.of(context).colorScheme.error,
        foregroundColor: Theme.of(context).colorScheme.onError,
        onPressed: state.stopRecording,
        icon: const Icon(Icons.stop),
        label: Text('ثبتول ودروه (${state.recordedSteps})'),
      );
    }
    if (state.session == SessionState.playing) {
      return FloatingActionButton.extended(
        onPressed: state.stopSession,
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('ودروه'),
      );
    }
    return FloatingActionButton.extended(
      onPressed: () async {
        final request = await showDialog<RecordRequest>(
          context: context,
          builder: (_) => const RecordDialog(),
        );
        if (request == null) return;
        await state.startRecording(
          name: request.name,
          url: request.url,
          captureScroll: request.captureScroll,
        );
      },
      icon: const Icon(Icons.fiber_manual_record),
      label: const Text('نوې لارښوونه'),
    );
  }
}
