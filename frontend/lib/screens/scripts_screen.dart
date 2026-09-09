import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/script.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/mac_widgets.dart';
import 'dashboard_screen.dart' show ScriptAvatar, RunStatePill, relativeTime;
import 'shell.dart';

enum _Filter { all, ok, failed }

class ScriptsScreen extends StatefulWidget {
  const ScriptsScreen({super.key});

  @override
  State<ScriptsScreen> createState() => _ScriptsScreenState();
}

class _ScriptsScreenState extends State<ScriptsScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scripts = _apply(state.scripts);

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'سکریپټونه',
            subtitle: state.scripts.isEmpty
                ? 'لا هېڅ سکریپټ نشته'
                : '${state.scripts.length} سکریپټه · ${state.totalStepCount} ګامه په ټوله کې',
            actions: [
              MacSegmented<_Filter>(
                value: _filter,
                items: const {
                  _Filter.all: 'ټول',
                  _Filter.ok: 'بریالي',
                  _Filter.failed: 'ناکام',
                },
                onChanged: (value) => setState(() => _filter = value),
              ),
              const SizedBox(width: 10),
              MacButton(
                label: 'نوی سکریپټ',
                icon: Icons.add_rounded,
                onPressed: () => newEmptyScriptFlow(context),
              ),
            ],
          ),
          if (state.scripts.isEmpty)
            const _EmptyState()
          else if (scripts.isEmpty)
            _NoMatches(onReset: () => setState(() => _filter = _Filter.all))
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 1020
                    ? 3
                    : (constraints.maxWidth > 700 ? 2 : 1);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    mainAxisExtent: 152,
                  ),
                  itemCount: scripts.length,
                  itemBuilder: (context, index) =>
                      ScriptCard(script: scripts[index], state: state),
                );
              },
            ),
        ],
      ),
    );
  }

  List<WebScript> _apply(List<WebScript> scripts) {
    switch (_filter) {
      case _Filter.all:
        return scripts;
      case _Filter.ok:
        return scripts.where((s) => s.lastRunOk == true).toList();
      case _Filter.failed:
        return scripts.where((s) => s.lastRunOk == false).toList();
    }
  }
}

class ScriptCard extends StatefulWidget {
  const ScriptCard({super.key, required this.script, required this.state});

  final WebScript script;
  final AppState state;

  @override
  State<ScriptCard> createState() => _ScriptCardState();
}

class _ScriptCardState extends State<ScriptCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final script = widget.script;
    final state = widget.state;
    final running =
        state.activeScriptId == script.id && state.session == SessionState.playing;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => state.openScript(script.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: mac.window,
            borderRadius: BorderRadius.circular(MacRadius.card),
            border: Border.all(
              color: _hover ? mac.accent.withOpacity(0.5) : mac.hairline,
              width: 0.8,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ScriptAvatar(
                    script: script,
                    color: mac.avatarFor(script.id),
                    size: 36,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          script.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: mac.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          script.startUrl.isEmpty
                              ? '—'
                              : script.startUrl.replaceFirst(RegExp(r'^https?://'), ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: mac.text2),
                        ),
                      ],
                    ),
                  ),
                  if (running)
                    SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: mac.accent),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  RunStatePill(script: script),
                  const SizedBox(width: 8),
                  MacPill('${script.stepCount} ګامه'),
                  const Spacer(),
                  Text(
                    relativeTime(script.lastRunAt ?? script.updatedAt),
                    style: TextStyle(fontSize: 11.5, color: mac.text3),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  MacButton(
                    label: 'چلول',
                    icon: Icons.play_arrow_rounded,
                    style: MacButtonStyle.primary,
                    onPressed: state.busy || script.stepCount == 0
                        ? null
                        : () => runScriptFlow(context, script),
                  ),
                  const SizedBox(width: 7),
                  MacButton(
                    label: '',
                    icon: Icons.edit_outlined,
                    tooltip: 'نوم بدلول',
                    onPressed: () => _rename(context),
                  ),
                  const SizedBox(width: 7),
                  MacButton(
                    label: '',
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'ړنګول',
                    onPressed: state.busy ? null : () => _delete(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final name = await promptText(
      context,
      title: 'نوم بدلول',
      initialValue: widget.script.name,
      label: 'نوم',
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.state.renameScript(widget.script.id, name.trim());
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = !widget.state.settings.confirmDelete ||
        await confirmSheet(
          context,
          title: 'سکریپټ ړنګول',
          message: '«${widget.script.name}» ړنګ کړم؟ دا کار بیرته نه کېږي.',
          confirmLabel: 'ړنګ کړه',
        );
    if (ok) await widget.state.deleteScript(widget.script.id);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 70),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: mac.accentSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.fiber_manual_record, size: 30, color: mac.accent),
          ),
          const SizedBox(height: 16),
          Text('لا هېڅ سکریپټ نشته',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: mac.text)),
          const SizedBox(height: 8),
          SizedBox(
            width: 460,
            child: Text(
              'د «نوې لارښوونه» تڼۍ ووهئ — براوزر پرانیستل کېږي، خپله لار یو ځل '
              'تعقیب کړئ (مینو ← تنظیمات ← ټم)، بیا ودرېږئ. له دې وروسته پروګرام '
              'هماغه لار پخپله ټکی په ټکی بیا ترسره کوي.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: mac.text2, height: 1.7),
            ),
          ),
          const SizedBox(height: 20),
          MacButton(
            label: 'نوې لارښوونه ثبت کړه',
            icon: Icons.fiber_manual_record,
            style: MacButtonStyle.primary,
            large: true,
            onPressed: () => startRecordingFlow(context),
          ),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Icon(Icons.filter_alt_off_outlined, size: 30, color: mac.text3),
          const SizedBox(height: 12),
          Text('پدې فلټر کې هېڅ سکریپټ نشته',
              style: TextStyle(fontSize: 13, color: mac.text2)),
          const SizedBox(height: 14),
          MacButton(label: 'ټول وښیه', onPressed: onReset),
        ],
      ),
    );
  }
}
