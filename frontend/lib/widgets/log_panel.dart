import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/script.dart';
import '../state/app_state.dart';

/// Live output coming from the backend (recording + replay).
class LogPanel extends StatefulWidget {
  const LogPanel({super.key, this.height = 200});

  final double height;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    _scrollToEnd();

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('پېښې', style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: state.log.isEmpty ? null : state.clearLog,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('پاکول'),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.log.isEmpty
                ? Center(
                    child: Text(
                      'لا هېڅ پېښه نشته',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    controller: _controller,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: state.log.length,
                    itemBuilder: (context, index) =>
                        _LogLine(event: state.log[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.event});

  final AppEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = event.isError
        ? theme.colorScheme.error
        : event.type == 'step_done'
            ? Colors.green.shade600
            : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon(event), size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              event.message,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon(AppEvent event) {
    if (event.isError) return Icons.error_outline;
    switch (event.type) {
      case 'step_recorded':
        return Icons.fiber_manual_record;
      case 'step_start':
        return Icons.play_arrow;
      case 'step_done':
        return Icons.check;
      case 'run_finished':
      case 'recording_saved':
        return Icons.flag_outlined;
      default:
        return Icons.info_outline;
    }
  }
}
