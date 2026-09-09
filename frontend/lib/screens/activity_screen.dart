import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/script.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/mac_widgets.dart';
import 'shell.dart';

enum _Filter { all, steps, errors }

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();
    final events = _apply(state.log).reversed.toList();

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'پېښې',
            subtitle: 'د ثبتولو او چلولو ژوندی جریان',
            actions: [
              MacSegmented<_Filter>(
                value: _filter,
                items: const {
                  _Filter.all: 'ټول',
                  _Filter.steps: 'ګامونه',
                  _Filter.errors: 'تېروتنې',
                },
                onChanged: (value) => setState(() => _filter = value),
              ),
              const SizedBox(width: 10),
              MacButton(
                label: 'پاکول',
                icon: Icons.clear_all_rounded,
                onPressed: state.log.isEmpty ? null : state.clearLog,
              ),
            ],
          ),
          MacCard(
            child: events.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.show_chart_rounded, size: 28, color: mac.text3),
                          const SizedBox(height: 12),
                          Text('لا هېڅ پېښه نشته',
                              style: TextStyle(fontSize: 13, color: mac.text2)),
                        ],
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      children: [
                        for (final event in events) EventLine(event: event),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<AppEvent> _apply(List<AppEvent> events) {
    switch (_filter) {
      case _Filter.all:
        return events;
      case _Filter.steps:
        return events
            .where((e) => e.type.startsWith('step_'))
            .toList();
      case _Filter.errors:
        return events.where((e) => e.isError).toList();
    }
  }
}

class EventLine extends StatelessWidget {
  const EventLine({super.key, required this.event, this.showTime = true});

  final AppEvent event;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final color = event.isError
        ? mac.red
        : (event.type == 'step_done' ? mac.green : mac.text2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconFor(event), size: 14, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              event.message,
              style: TextStyle(fontSize: 12, color: color, height: 1.45),
            ),
          ),
          if (showTime && event.ts > 0) ...[
            const SizedBox(width: 10),
            Text(
              _time(event.ts),
              style: TextStyle(fontSize: 11, color: mac.text3),
            ),
          ],
        ],
      ),
    );
  }

  static IconData iconFor(AppEvent event) {
    if (event.isError) return Icons.error_outline_rounded;
    switch (event.type) {
      case 'step_recorded':
        return Icons.fiber_manual_record;
      case 'step_start':
        return Icons.play_arrow_rounded;
      case 'step_done':
        return Icons.check_rounded;
      case 'run_started':
      case 'recording_started':
        return Icons.radio_button_checked;
      case 'run_finished':
      case 'recording_saved':
        return Icons.flag_outlined;
      default:
        return Icons.info_outline_rounded;
    }
  }

  static String _time(int epochMs) {
    final when = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
