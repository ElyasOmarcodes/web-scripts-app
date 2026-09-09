import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/mac_theme.dart';

/// Frameless macOS title bar: traffic lights on the left, a centred title,
/// and the window's toolbar on the right.
class MacTitleBar extends StatelessWidget {
  const MacTitleBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return SizedBox(
      height: height,
      child: DragToMoveArea(
        child: Container(
          decoration: BoxDecoration(
            color: mac.sidebar,
            border: Border(bottom: BorderSide(color: mac.hairline, width: 0.8)),
          ),
          child: Stack(
            children: [
              // The lights and the toolbar are pinned to physical edges so the
              // RTL layout never mirrors them into each other.
              const Positioned(left: 14, top: 0, bottom: 0, child: _TrafficLights()),
              Positioned.fill(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: mac.text,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 13, color: mac.text2),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 14,
                top: 0,
                bottom: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrafficLights extends StatefulWidget {
  const _TrafficLights();

  @override
  State<_TrafficLights> createState() => _TrafficLightsState();
}

class _TrafficLightsState extends State<_TrafficLights> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Light(
            color: const Color(0xFFFF5F57),
            glyph: Icons.close,
            hover: _hover,
            onTap: () async => windowManager.close(),
          ),
          const SizedBox(width: 8),
          _Light(
            color: const Color(0xFFFEBC2E),
            glyph: Icons.remove,
            hover: _hover,
            onTap: () async => windowManager.minimize(),
          ),
          const SizedBox(width: 8),
          _Light(
            color: const Color(0xFF28C840),
            glyph: Icons.open_in_full,
            hover: _hover,
            onTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _Light extends StatelessWidget {
  const _Light({
    required this.color,
    required this.glyph,
    required this.hover,
    required this.onTap,
  });

  final Color color;
  final IconData glyph;
  final bool hover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withOpacity(0.10), width: 0.5),
          ),
          // The glyph only appears while the pointer is over the cluster,
          // exactly like macOS.
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: hover ? 0.55 : 0,
            child: Icon(glyph, size: 8, color: Colors.black),
          ),
        ),
      ),
    );
  }
}
