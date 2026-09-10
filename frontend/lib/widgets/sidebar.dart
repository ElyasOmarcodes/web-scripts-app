import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/mac_theme.dart';
import 'mac_widgets.dart';

/// Translucent macOS source list.
class MacSidebar extends StatelessWidget {
  const MacSidebar({super.key});

  static const double width = 224;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final state = context.watch<AppState>();

    return Container(
      width: width,
      decoration: BoxDecoration(
        // A macOS source list is not one flat grey: the material catches a
        // little more light at the top than at the bottom.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
                mac.glassHighlight.withValues(alpha: 0.05), mac.sidebar),
            mac.sidebar,
          ],
        ),
        border: Border(
          // Physical: the sidebar sits on the right in this RTL layout.
          right: BorderSide(color: mac.hairline, width: 0.8),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SidebarSearch(),
          const SizedBox(height: 12),
          _label(context, 'اصلي'),
          _item(context, state, Icons.grid_view_rounded, 'داشبورډ',
              AppPage.dashboard),
          _item(context, state, Icons.description_outlined, 'سکریپټونه',
              AppPage.scripts,
              badge: state.scripts.isEmpty ? null : '${state.scripts.length}'),
          _item(
              context, state, Icons.checklist_rounded, 'کارونه', AppPage.tasks,
              badge: state.tasks.total == 0 ? null : '${state.tasks.total}',
              live: state.session == SessionState.runningTask),
          _item(context, state, Icons.switch_account_outlined, 'اکاونټونه',
              AppPage.accounts,
              badge:
                  state.accounts.total == 0 ? null : '${state.accounts.total}',
              live: state.session == SessionState.loggingIn),
          _item(context, state, Icons.fiber_manual_record, 'ثبتونکی',
              AppPage.recorder,
              live: state.session == SessionState.recording),
          _item(context, state, Icons.show_chart_rounded, 'پېښې',
              AppPage.activity),
          _label(context, 'نور'),
          _item(context, state, Icons.settings_outlined, 'تنظیمات',
              AppPage.settings),
          _item(context, state, Icons.help_outline_rounded, 'مرسته',
              AppPage.help),
          const Spacer(),
          _Footer(state: state),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    final mac = MacPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: mac.text3),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    AppState state,
    IconData icon,
    String label,
    AppPage target, {
    String? badge,
    bool live = false,
  }) {
    return _SidebarItem(
      icon: icon,
      label: label,
      badge: badge,
      live: live,
      selected: state.page == target,
      onTap: () => state.navigate(target),
    );
  }
}

class _SidebarSearch extends StatelessWidget {
  const _SidebarSearch();

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: mac.fill,
        borderRadius: BorderRadius.circular(MacRadius.control),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 14, color: mac.text3),
          const SizedBox(width: 6),
          Text('لټون', style: TextStyle(fontSize: 12.5, color: mac.text3)),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
    this.live = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  final bool live;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final foreground = widget.selected ? Colors.white : mac.text;
    final iconColor =
        widget.selected ? Colors.white : (widget.live ? mac.red : mac.text2);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          height: 30,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? null
                : (_hover ? mac.fill : Colors.transparent),
            // The selected row is a filled accent capsule with a faint
            // top-to-bottom shade and its own small shadow, as in Sonoma.
            gradient: widget.selected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.alphaBlend(
                          Colors.white.withValues(alpha: 0.14), mac.accent),
                      mac.accent,
                    ],
                  )
                : null,
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: mac.accent.withValues(alpha: 0.30),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
            borderRadius: BorderRadius.circular(MacRadius.row),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 17,
                child: Icon(widget.icon,
                    size: widget.live ? 12 : 16, color: iconColor),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(fontSize: 13, color: foreground),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: widget.selected ? Colors.white24 : mac.fill2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.badge!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: widget.selected ? Colors.white : mac.text2,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);

    late final Color color;
    late final String label;
    if (!state.connected) {
      color = mac.text3;
      label = 'سرور نه دی نښتی';
    } else if (state.session == SessionState.recording) {
      color = mac.red;
      label = 'ثبتول روان دي';
    } else if (state.session == SessionState.playing) {
      color = mac.accent;
      label = 'چلول روان دي';
    } else {
      final active = state.browsers.activeBrowser;
      color = active == null ? mac.orange : mac.green;
      label = active == null ? 'براوزر ونه موندل شو' : 'براوزر: ${active.name}';
    }

    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: mac.hairline, width: 0.8)),
      ),
      child: Row(
        children: [
          StatusDot(color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11.5, color: mac.text2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
