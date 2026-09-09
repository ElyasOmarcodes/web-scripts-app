import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings.dart';
import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/mac_widgets.dart';
import 'shell.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'تنظیمات',
            subtitle: 'براوزر، ښکارېدنه او د چلولو چلند',
            actions: [
              MacButton(
                label: state.refreshingBrowsers ? 'لټون…' : 'بیا لټون',
                icon: Icons.refresh_rounded,
                onPressed: state.refreshingBrowsers
                    ? null
                    : () => state.refreshBrowsers(rescan: true),
              ),
            ],
          ),
          const MacGroupTitle('براوزر'),
          _BrowserGroup(state: state),
          const MacGroupTitle('ښکارېدنه'),
          _AppearanceGroup(state: state, settings: settings),
          const MacGroupTitle('چلول'),
          _PlaybackGroup(state: state, settings: settings),
          const MacGroupTitle('ذخیره او نور'),
          _StorageGroup(state: state, settings: settings),
        ],
      ),
    );
  }
}

class _BrowserGroup extends StatelessWidget {
  const _BrowserGroup({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final list = state.browsers;
    final active = list.activeBrowser;
    final selected = state.settings.browser;

    return MacGroup(
      children: [
        MacRow(
          leading: _Radio(on: selected == 'auto'),
          title: 'اتوماتیک غوره کول',
          subtitle: 'لومړی Edge، بیا Chrome، بیا هر موجود Chromium',
          onTap: () => state.updateSettings({'browser': 'auto'}),
          trailing: active == null
              ? MacPill('براوزر ونه موندل شو',
                  color: mac.orange, background: mac.orange.withOpacity(0.16))
              : MacPill('اوس: ${active.name}',
                  color: mac.accent, background: mac.accentSoft),
        ),
        if (list.browsers.isEmpty)
          MacRow(
            title: 'د براوزرونو لټون روان دی…',
            subtitle: 'که دا پیغام پاتې شي، «بیا لټون» ووهئ',
          )
        else
          ...list.browsers.map(
            (browser) => _BrowserRow(
              browser: browser,
              selected: selected == browser.id,
              onTap: browser.usable
                  ? () => state.updateSettings({'browser': browser.id})
                  : null,
            ),
          ),
      ],
    );
  }
}

class _BrowserRow extends StatelessWidget {
  const _BrowserRow({
    required this.browser,
    required this.selected,
    this.onTap,
  });

  final BrowserInfo browser;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);

    late final Widget badge;
    if (!browser.supported) {
      badge = const MacPill('ملاتړ نه کېږي');
    } else if (browser.installed) {
      badge = MacPill('نصب دی',
          color: mac.green, background: mac.green.withOpacity(0.16));
    } else {
      badge = const MacPill('نه دی موندل شوی');
    }

    final subtitle = browser.installed
        ? [
            if (browser.shortVersion.isNotEmpty) browser.shortVersion,
            if (browser.path.isNotEmpty) _shortPath(browser.path),
          ].join(' · ')
        : (browser.supported
            ? 'پدې کمپیوټر کې ونه موندل شو'
            : 'دا براوزر لا ملاتړ نه کېږي (Chromium پکار دی)');

    return Opacity(
      opacity: browser.usable ? 1 : 0.62,
      child: MacRow(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Radio(on: selected, enabled: browser.usable),
            const SizedBox(width: 10),
            StatusDot(color: browser.installed ? mac.green : mac.text3),
          ],
        ),
        title: browser.name,
        subtitle: subtitle,
        trailing: badge,
        onTap: onTap,
      ),
    );
  }

  /// Keeps only the last few path segments so the row stays on one line.
  static String _shortPath(String path) {
    final separator = path.contains(r'\') ? r'\' : '/';
    final parts = path.split(RegExp(r'[\\/]'));
    if (parts.length <= 4) return path;
    return '…$separator${parts.sublist(parts.length - 3).join(separator)}';
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.on, this.enabled = true});

  final bool on;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? mac.accent : Colors.transparent,
        border: Border.all(
          color: on ? mac.accent : (enabled ? mac.text3 : mac.hairline),
          width: 1.2,
        ),
      ),
      child: on
          ? Center(
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
              ),
            )
          : null,
    );
  }
}

class _AppearanceGroup extends StatelessWidget {
  const _AppearanceGroup({required this.state, required this.settings});

  final AppState state;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return MacGroup(
      children: [
        MacRow(
          title: 'ښکارېدنه',
          subtitle: 'د سیسټم سره سم بدلېږي',
          trailing: MacSegmented<String>(
            value: settings.theme,
            items: const {'system': 'سیسټم', 'light': 'رڼا', 'dark': 'تیاره'},
            onChanged: (value) => state.updateSettings({'theme': value}),
          ),
        ),
        MacRow(
          title: 'د تاکید رنګ',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: macAccents.entries.map((entry) {
              final selected = settings.accent == entry.key;
              return Padding(
                padding: const EdgeInsets.only(right: 9),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => state.updateSettings({'accent': entry.key}),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: entry.value,
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: entry.value.withOpacity(0.9),
                                  spreadRadius: 1.5,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _PlaybackGroup extends StatelessWidget {
  const _PlaybackGroup({required this.state, required this.settings});

  final AppState state;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return MacGroup(
      children: [
        MacRow(
          title: 'د چلولو چټکتیا',
          subtitle: 'لوړه چټکتیا = لنډ ځنډونه',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MacSlider(
                value: settings.speed,
                min: 0.5,
                max: 4,
                divisions: 7,
                onChanged: (value) => state.updateSettings({'speed': value}),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 36,
                child: Text('${settings.speed.toStringAsFixed(1)}×',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: mac.text)),
              ),
            ],
          ),
        ),
        MacRow(
          title: 'پټ چلول (headless)',
          subtitle: 'براوزر نه ښکاري — ګړندی دی، خو ځینې سایټونه یې نه خوښوي',
          trailing: MacSwitch(
            value: settings.headless,
            onChanged: (value) => state.updateSettings({'headless': value}),
          ),
        ),
        MacRow(
          title: 'براوزر پرانیستی پرېږده',
          subtitle: 'د چلولو له پای ته رسېدو وروسته کړکۍ نه تړل کېږي',
          trailing: MacSwitch(
            value: settings.keepOpen,
            onChanged: (value) => state.updateSettings({'keep_open': value}),
          ),
        ),
        MacRow(
          title: 'ننوتنې وساته',
          subtitle: 'ځانګړی پروفایل — یو ځل ننوځئ، تل ننوتلي یاست',
          trailing: MacSwitch(
            value: settings.useProfile,
            onChanged: (value) => state.updateSettings({'use_profile': value}),
          ),
        ),
        MacRow(
          title: 'د ګام انتظار',
          subtitle: 'تر څو یو عنصر ونه موندل شي',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MacIconButton(
                icon: Icons.remove_rounded,
                onPressed: settings.stepTimeout <= 3
                    ? null
                    : () => state.updateSettings(
                        {'step_timeout': settings.stepTimeout - 5}),
              ),
              SizedBox(
                width: 62,
                child: Text('${settings.stepTimeout.round()} ثانیې',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: mac.text)),
              ),
              MacIconButton(
                icon: Icons.add_rounded,
                onPressed: settings.stepTimeout >= 120
                    ? null
                    : () => state.updateSettings(
                        {'step_timeout': settings.stepTimeout + 5}),
              ),
            ],
          ),
        ),
        MacRow(
          title: 'د سکرول ثبتول',
          subtitle: 'د ثبتولو پر مهال سکرول هم ثبت کړه',
          trailing: MacSwitch(
            value: settings.captureScroll,
            onChanged: (value) => state.updateSettings({'capture_scroll': value}),
          ),
        ),
      ],
    );
  }
}

class _StorageGroup extends StatelessWidget {
  const _StorageGroup({required this.state, required this.settings});

  final AppState state;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return MacGroup(
      children: [
        MacRow(
          leading: Icon(Icons.folder_outlined, size: 18, color: mac.text2),
          title: 'د سکریپټونو فولډر',
          subtitle: r'%LOCALAPPDATA%\WebScripts\scripts',
        ),
        MacRow(
          leading: Icon(Icons.shield_outlined, size: 18, color: mac.text2),
          title: 'د براوزر پروفایل',
          subtitle: r'%LOCALAPPDATA%\WebScripts\edge-profile — ستاسو ننوتنې پکې دي',
        ),
        MacRow(
          leading: Icon(Icons.delete_sweep_outlined, size: 18, color: mac.text2),
          title: 'د ړنګولو پوښتنه',
          subtitle: 'د ړنګولو دمخه تایید وغواړه',
          trailing: MacSwitch(
            value: settings.confirmDelete,
            onChanged: (value) => state.updateSettings({'confirm_delete': value}),
          ),
        ),
        MacRow(
          leading: Icon(Icons.restart_alt_rounded, size: 18, color: mac.text2),
          title: 'تنظیمات بیا اصلي کول',
          subtitle: 'ټول تنظیمات لومړني حالت ته ستنېږي',
          trailing: MacButton(
            label: 'بیا اصلي کول',
            onPressed: () async {
              final ok = await confirmSheet(
                context,
                title: 'تنظیمات بیا اصلي کړم؟',
                message: 'ټول تنظیمات لومړني حالت ته ستنېږي. سکریپټونه نه ړنګېږي.',
                confirmLabel: 'بیا اصلي کړه',
                destructive: false,
              );
              if (ok) await state.resetSettings();
            },
          ),
        ),
      ],
    );
  }
}
