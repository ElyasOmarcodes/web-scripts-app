import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/mac_widgets.dart';
import 'shell.dart';

class RecorderScreen extends StatelessWidget {
  const RecorderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return state.session == SessionState.recording
        ? _LiveRecording(state: state)
        : _RecorderIdle(state: state);
  }
}

class _RecorderIdle extends StatelessWidget {
  const _RecorderIdle({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final active = state.browsers.activeBrowser;

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            title: 'ثبتونکی',
            subtitle: 'خپله لار یو ځل وښایاست، پروګرام به یې زده کړي',
          ),
          MacCard(
            padding: const EdgeInsets.symmetric(vertical: 46, horizontal: 26),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: mac.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.fiber_manual_record, size: 32, color: mac.red),
                ),
                const SizedBox(height: 18),
                Text('ثبتول پیل کړئ',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: mac.text)),
                const SizedBox(height: 8),
                SizedBox(
                  width: 520,
                  child: Text(
                    'براوزر پرانیستل کېږي. هر کلیک، هر متن او هر انتخاب چې کوئ '
                    'ثبتېږي. کله چې ودرېږئ، ټوله لار د یوه سکریپټ په توګه خوندي کېږي.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: mac.text2, height: 1.7),
                  ),
                ),
                const SizedBox(height: 20),
                MacButton(
                  label: 'نوې لارښوونه ثبت کړه',
                  icon: Icons.fiber_manual_record,
                  style: MacButtonStyle.danger,
                  large: true,
                  onPressed: state.busy ? null : () => startRecordingFlow(context),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    StatusDot(color: active == null ? mac.orange : mac.green),
                    const SizedBox(width: 8),
                    Text(
                      active == null
                          ? 'ملاتړ شوی براوزر ونه موندل شو — تنظیمات وګورئ'
                          : 'براوزر: ${active.name}'
                              '${active.shortVersion.isEmpty ? '' : ' ${active.shortVersion}'}',
                      style: TextStyle(fontSize: 12, color: mac.text2),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _HowItWorks(),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    const steps = [
      ('۱', 'نوم او پیل پته ورکړئ', 'مثلاً «د فیسبوک ټم» او facebook.com'),
      ('۲', 'په براوزر کې خپل کار وکړئ', 'مینو ← تنظیمات ← ښکارېدنه ← تیاره ټم'),
      ('۳', '«ثبتول ودروه» ووهئ', 'سکریپټ خوندي شو — هر وخت یې چلولی شئ'),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          Expanded(
            child: MacCard(
              padding: const EdgeInsets.all(15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: mac.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Text(steps[i].$1,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: mac.accent)),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(steps[i].$2,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: mac.text)),
                        const SizedBox(height: 3),
                        Text(steps[i].$3,
                            style: TextStyle(
                                fontSize: 11.5, color: mac.text2, height: 1.45)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LiveRecording extends StatefulWidget {
  const _LiveRecording({required this.state});

  final AppState state;

  @override
  State<_LiveRecording> createState() => _LiveRecordingState();
}

class _LiveRecordingState extends State<_LiveRecording>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Keeps the elapsed-time pill moving.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  String get _elapsed {
    final started = widget.state.sessionStartedAt;
    if (started == null) return '۰۰:۰۰';
    final seconds = DateTime.now().difference(started).inSeconds;
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = widget.state;
    final steps = state.liveSteps;
    final last = steps.isEmpty ? null : steps.last;
    final active = state.browsers.activeBrowser;
    final pages = steps
        .map((s) => s.url ?? '')
        .where((u) => u.isNotEmpty)
        .toSet()
        .length;

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            leading: FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0.25).animate(_pulse),
              child: StatusDot(color: mac.red, glow: true, size: 9),
            ),
            title: 'ثبتول روان دي…',
            subtitle: 'په براوزر کې خپل کار وکړئ — هر کلیک ثبتېږي',
            actions: [
              MacPill(_elapsed, color: mac.red, background: mac.red.withValues(alpha: 0.14)),
              const SizedBox(width: 10),
              MacButton(
                label: 'ثبتول ودروه',
                icon: Icons.stop_rounded,
                style: MacButtonStyle.danger,
                onPressed: state.stopRecording,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _LiveCard(
                  gradient: 'blue',
                  icon: Icons.ads_click_rounded,
                  label: 'ثبت شوي ګامونه',
                  value: '${state.recordedSteps}',
                  hint: last == null ? 'د لومړي کار انتظار…' : last.description,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _LiveCard(
                  gradient: 'purple',
                  icon: Icons.public_rounded,
                  label: 'اوسنۍ پاڼه',
                  value: _host(last?.url),
                  valueSize: 17,
                  hint: '$pages پاڼې لیدل شوې',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _LiveCard(
                  gradient: 'green',
                  icon: Icons.keyboard_alt_outlined,
                  label: 'براوزر',
                  value: active?.name.split(' ').last ?? '—',
                  valueSize: 19,
                  hint: state.settings.useProfile
                      ? 'پروفایل فعال — ننوتنې ساتل کېږي'
                      : 'پروفایل غیرفعال',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
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
                      FadeTransition(
                        opacity: Tween<double>(begin: 1, end: 0.25).animate(_pulse),
                        child: StatusDot(color: mac.red, size: 8),
                      ),
                      const SizedBox(width: 8),
                      Text('ژوندي ګامونه',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: mac.text)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    children: [
                      for (var i = 0; i < steps.length; i++)
                        _LiveStep(index: i, description: steps[i].description,
                            locator: steps[i].targets.isEmpty
                                ? ''
                                : steps[i].targets.first.value),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            const SizedBox(width: 11),
                            Container(
                              width: 21,
                              height: 21,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: mac.fill2, shape: BoxShape.circle),
                              child: Text('…',
                                  style:
                                      TextStyle(fontSize: 11, color: mac.text3)),
                            ),
                            const SizedBox(width: 11),
                            Text('د راتلونکي کار انتظار…',
                                style:
                                    TextStyle(fontSize: 12.5, color: mac.text3)),
                          ],
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
    );
  }

  String _host(String? url) {
    if (url == null || url.isEmpty) return '—';
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri.host.isEmpty ? url : uri.host.replaceFirst('www.', '');
  }
}

class _LiveStep extends StatelessWidget {
  const _LiveStep({
    required this.index,
    required this.description,
    required this.locator,
  });

  final int index;
  final String description;
  final String locator;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 260),
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 6), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 21,
              height: 21,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: mac.green.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Text('${index + 1}',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: mac.green)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(description,
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
          ],
        ),
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({
    required this.gradient,
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    this.valueSize = 29,
  });

  final String gradient;
  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final double valueSize;

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
            color: colors.first.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -30,
            top: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
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
                    Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.92)),
                    const SizedBox(width: 6),
                    Text(label,
                        style: TextStyle(
                            fontSize: 12, color: Colors.white.withValues(alpha: 0.92))),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: valueSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: Colors.white,
                          height: 1.15,
                        )),
                    Text(hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: 0.85))),
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
