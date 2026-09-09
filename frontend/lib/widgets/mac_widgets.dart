import 'package:flutter/material.dart';

import '../theme/mac_theme.dart';

/// Small reusable controls shaped like their macOS counterparts.

enum MacButtonStyle { normal, primary, danger, ghost }

class MacButton extends StatefulWidget {
  const MacButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.style = MacButtonStyle.normal,
    this.large = false,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final MacButtonStyle style;
  final bool large;
  final String? tooltip;

  @override
  State<MacButton> createState() => _MacButtonState();
}

class _MacButtonState extends State<MacButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final enabled = widget.onPressed != null;

    Color background;
    Color foreground;
    Border? border;
    List<BoxShadow>? shadow;

    switch (widget.style) {
      case MacButtonStyle.primary:
        background = mac.accent;
        foreground = Colors.white;
        break;
      case MacButtonStyle.danger:
        background = mac.red;
        foreground = Colors.white;
        break;
      case MacButtonStyle.ghost:
        background = _hover ? mac.fill : Colors.transparent;
        foreground = mac.text2;
        break;
      case MacButtonStyle.normal:
        background = mac.window;
        foreground = mac.text;
        border = Border.all(color: mac.hairline, width: 0.8);
        shadow = [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 1.5, offset: const Offset(0, 1)),
        ];
        break;
    }

    if (!enabled) {
      background = widget.style == MacButtonStyle.normal ? background : mac.fill;
      foreground = mac.text3;
      shadow = null;
    } else if (_down) {
      background = Color.alphaBlend(Colors.black.withOpacity(0.09), background);
    } else if (_hover && widget.style != MacButtonStyle.ghost) {
      background = Color.alphaBlend(Colors.black.withOpacity(0.035), background);
    }

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      height: widget.large ? 34 : 30,
      padding: EdgeInsets.symmetric(horizontal: widget.label.isEmpty ? 9 : (widget.large ? 16 : 13)),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(widget.large ? 8 : MacRadius.row),
        border: border,
        boxShadow: shadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null)
            Icon(widget.icon, size: widget.large ? 16 : 15, color: foreground),
          if (widget.icon != null && widget.label.isNotEmpty) const SizedBox(width: 7),
          if (widget.label.isNotEmpty)
            Text(
              widget.label,
              style: TextStyle(
                fontSize: widget.large ? 13.5 : 13,
                color: foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );

    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: child,
      ),
    );

    return widget.tooltip == null
        ? button
        : Tooltip(message: widget.tooltip!, waitDuration: const Duration(milliseconds: 500), child: button);
  }
}

/// Round icon-only button used in toolbars and rows.
class MacIconButton extends StatefulWidget {
  const MacIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 15,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;

  @override
  State<MacIconButton> createState() => _MacIconButtonState();
}

class _MacIconButtonState extends State<MacIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final enabled = widget.onPressed != null;
    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          width: 28,
          height: 26,
          decoration: BoxDecoration(
            color: _hover && enabled ? mac.fill : Colors.transparent,
            borderRadius: BorderRadius.circular(MacRadius.control),
          ),
          child: Icon(
            widget.icon,
            size: widget.size,
            color: enabled ? (widget.color ?? mac.text2) : mac.text3,
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? button
        : Tooltip(message: widget.tooltip!, waitDuration: const Duration(milliseconds: 500), child: button);
  }
}

class MacSwitch extends StatelessWidget {
  const MacSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final enabled = onChanged != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 38,
            height: 22,
            decoration: BoxDecoration(
              color: value ? mac.green : mac.fill2,
              borderRadius: BorderRadius.circular(11),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(2),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 3, offset: const Offset(0, 1)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MacSegmented<T> extends StatelessWidget {
  const MacSegmented({
    super.key,
    required this.items,
    required this.value,
    this.onChanged,
  });

  final Map<T, String> items;
  final T value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: mac.fill,
        borderRadius: BorderRadius.circular(MacRadius.row),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.entries.map((entry) {
          final selected = entry.key == value;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onChanged == null ? null : () => onChanged!(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                decoration: BoxDecoration(
                  color: selected ? mac.window : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: selected
                      ? [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 2, offset: const Offset(0, 1))]
                      : null,
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: selected ? mac.text : mac.text2,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class MacSlider extends StatelessWidget {
  const MacSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.onChanged,
    this.width = 150,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return SizedBox(
      width: width,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 4,
          activeTrackColor: mac.accent,
          inactiveTrackColor: mac.fill2,
          thumbColor: Colors.white,
          overlayShape: SliderComponentShape.noOverlay,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.5, elevation: 2),
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class MacCard extends StatelessWidget {
  const MacCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.clip = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color ?? mac.window,
        borderRadius: BorderRadius.circular(MacRadius.card),
        border: Border.all(color: mac.hairline, width: 0.8),
      ),
      child: child,
    );
  }
}

class MacPill extends StatelessWidget {
  const MacPill(this.label, {super.key, this.color, this.background});

  final String label;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? mac.fill2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color ?? mac.text2,
        ),
      ),
    );
  }
}

class MacField extends StatelessWidget {
  const MacField({
    super.key,
    this.controller,
    this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.onSubmitted,
    this.prefix,
  });

  final TextEditingController? controller;
  final String? hint;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefix;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: mac.window,
        borderRadius: BorderRadius.circular(MacRadius.control),
        border: Border.all(color: mac.hairline, width: 0.8),
      ),
      child: Row(
        children: [
          if (prefix != null) ...[prefix!, const SizedBox(width: 6)],
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              autofocus: autofocus,
              onSubmitted: onSubmitted,
              cursorWidth: 1.2,
              style: TextStyle(fontSize: 13, color: mac.text),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.only(bottom: 2),
                hintText: hint,
                hintStyle: TextStyle(fontSize: 13, color: mac.text3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section label above a settings group.
class MacGroupTitle extends StatelessWidget {
  const MacGroupTitle(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: mac.text2),
      ),
    );
  }
}

/// One row inside a settings group (System Settings look).
class MacRow extends StatelessWidget {
  const MacRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    return InkWell(
      onTap: onTap,
      hoverColor: mac.fill,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, color: mac.text)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: TextStyle(fontSize: 11.5, color: mac.text2, height: 1.35)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Groups rows with hairline separators, like a System Settings section.
class MacGroup extends StatelessWidget {
  const MacGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mac = MacPalette.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 0.8, thickness: 0.8, color: mac.hairline));
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: MacCard(child: Column(mainAxisSize: MainAxisSize.min, children: rows)),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.glow = false, this.size = 7});

  final Color color;
  final bool glow;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: glow
            ? [BoxShadow(color: color.withOpacity(0.35), blurRadius: 0, spreadRadius: 3)]
            : null,
      ),
    );
  }
}
