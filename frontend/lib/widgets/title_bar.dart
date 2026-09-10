import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/mac_theme.dart';

/// Frameless title bar: a centred title, the window's toolbar, and the window
/// buttons on the right where every Windows program keeps them.
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
            // The title bar is its own material in macOS: slightly lighter at
            // the very top, with a hairline that separates it from the window.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                    mac.glassHighlight.withValues(alpha: 0.06), mac.sidebar),
                mac.sidebar,
              ],
            ),
            border: Border(bottom: BorderSide(color: mac.hairline, width: 0.8)),
          ),
          child: Stack(
            children: [
              // Pinned to physical edges so the RTL layout never mirrors the
              // window buttons into the toolbar.
              const Positioned(
                  right: 14, top: 0, bottom: 0, child: _WindowButtons()),
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
                left: 14,
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

/// The three lights. Colours and behaviour are macOS; the order is the one
/// Windows users reach for — minimise, maximise, close, with close outermost.
class _WindowButtons extends StatefulWidget {
  const _WindowButtons();

  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Directionality(
        // Physical order, whatever the page direction is.
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Light(
              color: const Color(0xFFFEBC2E),
              glyph: _Glyph.minimize,
              hover: _hover,
              tooltip: 'کوچنی کول',
              onTap: () async => windowManager.minimize(),
            ),
            const SizedBox(width: 8),
            _Light(
              color: const Color(0xFF28C840),
              glyph: _Glyph.zoom,
              hover: _hover,
              tooltip: 'ټوله پرده',
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            const SizedBox(width: 8),
            _Light(
              color: const Color(0xFFFF5F57),
              glyph: _Glyph.close,
              hover: _hover,
              tooltip: 'تړل',
              onTap: () async => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Glyph { close, minimize, zoom }

class _Light extends StatelessWidget {
  const _Light({
    required this.color,
    required this.glyph,
    required this.hover,
    required this.tooltip,
    required this.onTap,
  });

  final Color color;
  final _Glyph glyph;
  final bool hover;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.black.withValues(alpha: 0.10), width: 0.5),
            ),
            // The glyph only appears while the pointer is over the cluster,
            // exactly like macOS.
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: hover ? 1 : 0,
              child: CustomPaint(painter: _GlyphPainter(glyph)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the marks macOS puts inside the lights.
///
/// They are shapes, not font icons: a hairline cross, a hairline dash, and the
/// two little filled triangles of the zoom button. Material's icons at 8px are
/// muddy blobs by comparison.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph);

  final _Glyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0xCC000000)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final centre = size.center(Offset.zero);

    switch (glyph) {
      case _Glyph.close:
        const r = 2.6;
        canvas.drawLine(centre.translate(-r, -r), centre.translate(r, r), ink);
        canvas.drawLine(centre.translate(r, -r), centre.translate(-r, r), ink);
        break;
      case _Glyph.minimize:
        canvas.drawLine(
            centre.translate(-3.2, 0), centre.translate(3.2, 0), ink);
        break;
      case _Glyph.zoom:
        // Two triangles pointing away from each other, filled.
        final fill = Paint()..color = const Color(0xCC000000);
        const r = 3.2;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx - r, centre.dy - r)
            ..lineTo(centre.dx + 0.6, centre.dy - r)
            ..lineTo(centre.dx - r, centre.dy + 0.6)
            ..close(),
          fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx + r, centre.dy + r)
            ..lineTo(centre.dx - 0.6, centre.dy + r)
            ..lineTo(centre.dx + r, centre.dy - 0.6)
            ..close(),
          fill,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) => oldDelegate.glyph != glyph;
}
