import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/script.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import 'dialogs.dart';
import 'mac_widgets.dart';

/// Settings that belong to one script rather than to the whole app.
Future<void> scriptSettingsFlow(BuildContext context, WebScript script) async {
  final state = context.read<AppState>();
  final saved = await showMacSheet<Map<String, dynamic>>(
    context,
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: _ScriptSettingsSheet(script: script),
    ),
  );
  if (saved != null) await state.updateScript(script.id, saved);
}

class _ScriptSettingsSheet extends StatefulWidget {
  const _ScriptSettingsSheet({required this.script});

  final WebScript script;

  @override
  State<_ScriptSettingsSheet> createState() => _ScriptSettingsSheetState();
}

class _ScriptSettingsSheetState extends State<_ScriptSettingsSheet> {
  late bool _own;
  late double _min;
  late double _max;

  @override
  void initState() {
    super.initState();
    _own = widget.script.gapMinMs != null;
    _min = (widget.script.gapMinMs ?? 500).toDouble();
    _max = (widget.script.gapMaxMs ?? 1500).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final settings = context.watch<AppState>().settings;

    return MacSheet(
      title: 'د سکریپټ تنظیمات',
      subtitle: widget.script.name,
      icon: Icons.tune_rounded,
      width: 540,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          MacRow(
            title: 'د دې سکریپټ خپله فاصله',
            subtitle: _own
                ? 'د ټولو تنظیماتو پر ځای، دا سکریپټ خپله فاصله کاروي'
                : 'اوس د عمومي تنظیماتو فاصله کاروي '
                    '(${(settings.humanMinGap * 1000).round()}–'
                    '${(settings.humanMaxGap * 1000).round()} ms)',
            trailing: MacSwitch(
              value: _own,
              onChanged: (value) => setState(() => _own = value),
            ),
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: _own ? 1 : 0.45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetLabel('د دوو کړنو تر منځ تصادفي فاصله'),
                _GapSlider(
                  label: 'لږ تر لږه',
                  value: _min,
                  max: 10000,
                  enabled: _own,
                  onChanged: (value) => setState(() {
                    _min = value;
                    if (_max < _min) _max = _min;
                  }),
                ),
                const SizedBox(height: 6),
                _GapSlider(
                  label: 'تر ټولو زیات',
                  value: _max,
                  max: 20000,
                  enabled: _own,
                  onChanged: (value) => setState(() {
                    _max = value;
                    if (_min > _max) _min = _max;
                  }),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                  decoration: BoxDecoration(
                    color: mac.fill,
                    borderRadius: BorderRadius.circular(MacRadius.card),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 15, color: mac.text2),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'هر ګام به د ${_min.round()} او ${_max.round()} '
                          'ملي ثانیو تر منځ یوه تصادفي شېبه انتظار وکړي — '
                          'د ${widget.script.stepCount} ګامو لپاره نږدې '
                          '${((_min + _max) / 2 * widget.script.stepCount / 1000).round()} '
                          'ثانیې.',
                          style: TextStyle(
                              fontSize: 12, color: mac.text2, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        MacButton(
          label: 'خوندي کړه',
          icon: Icons.check_rounded,
          style: MacButtonStyle.primary,
          large: true,
          onPressed: () => Navigator.of(context).pop({
            'gap_min_ms': _own ? _min.round() : null,
            'gap_max_ms': _own ? _max.round() : null,
          }),
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

class _GapSlider extends StatelessWidget {
  const _GapSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Row(
      children: [
        SizedBox(
          width: 78,
          child:
              Text(label, style: TextStyle(fontSize: 12.5, color: mac.text2)),
        ),
        Expanded(
          child: MacSlider(
            value: value.clamp(0, max),
            min: 0,
            max: max,
            divisions: (max / 100).round(),
            onChanged: enabled ? onChanged : null,
          ),
        ),
        SizedBox(
          width: 74,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '${value.round()} ms',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: mac.text),
            ),
          ),
        ),
      ],
    );
  }
}
