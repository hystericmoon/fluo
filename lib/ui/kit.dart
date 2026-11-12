import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../data/models.dart';
import '../theme/tokens.dart';
import '../theme/accent.dart';

/// Pushes a screen with a short fade. Motion polish comes in session 8.
Route<T> fluoRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 160),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (ctx, anim, _, child) {
        if (MediaQuery.maybeDisableAnimationsOf(ctx) ?? false) return child;
        return FadeTransition(opacity: anim, child: child);
      },
    );

/// Base tappable: focus ring, press feedback, keyboard activation, semantics.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.label,
    this.radius = 10,
    this.toggled,
    this.selected,
    this.checked,
    this.isButton = true,
    this.actions,
  });

  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool pressed) builder;
  final String? label;
  final double radius;
  final bool? toggled;
  final bool? selected;
  final bool? checked;
  final bool isButton;

  /// Extra screen reader actions on this control (TalkBack "actions" menu).
  /// Kept on the control itself so they never fuse neighbouring controls.
  final Map<CustomSemanticsAction, VoidCallback>? actions;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: widget.isButton,
      enabled: enabled,
      label: widget.label,
      toggled: widget.toggled,
      selected: widget.selected,
      checked: widget.checked,
      inMutuallyExclusiveGroup: widget.checked != null ? true : null,
      customSemanticsActions: widget.actions,
      onTap: widget.onTap,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          // The Semantics above owns the tap action; a second node would make
          // TalkBack stop twice on every control.
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // An explicit label replaces the visual text for screen readers.
              ExcludeSemantics(
                excluding: widget.label != null,
                child: Opacity(
                  opacity: _pressed ? 0.8 : 1,
                  child: widget.builder(context, _pressed),
                ),
              ),
              if (_focused)
                Positioned(
                  left: -4,
                  top: -4,
                  right: -4,
                  bottom: -4,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.radius + 4),
                        border: Border.all(color: context.accent.color, width: 2),
                      ),
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

enum BtnKind { primary, outline, danger }

class FluoButton extends StatelessWidget {
  const FluoButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = BtnKind.outline,
    this.icon,
    this.height = 44,
    this.radius = 10,
    this.hPad = 16,
    this.fontSize = 15,
    this.weight = FontWeight.w500,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final BtnKind kind;
  final IconData? icon;
  final double height;
  final double radius;
  final double hPad;
  final double fontSize;
  final FontWeight weight;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      BtnKind.primary => (context.accent.color, context.accent.onColor, null),
      BtnKind.outline => (null, FluoColors.fg, FluoColors.borderStrong),
      BtnKind.danger => (null, FluoColors.bug, FluoColors.bug),
    };
    return Pressable(
      onTap: onPressed,
      radius: radius,
      builder: (_, _) => Opacity(
        // Disabled: no handler. Dimmed, and the semantics node is not enabled.
        opacity: onPressed == null ? 0.45 : 1,
        child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: hPad),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: border == null ? null : Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: fs(fontSize, w: weight, c: fg)),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// 44dp square outlined icon button (back, settings, delete).
class FluoIconButton extends StatelessWidget {
  const FluoIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 44,
    this.radius = 10,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      label: label,
      radius: radius,
      builder: (_, _) => Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: FluoColors.borderStrong),
          ),
          child: Icon(icon, size: 20, color: FluoColors.fg),
        ),
      ),
    );
  }
}

/// Dot that tells severity by shape as well as colour.
class SeverityDot extends StatelessWidget {
  const SeverityDot(this.severity, {super.key});
  final Severity severity;

  @override
  Widget build(BuildContext context) {
    return switch (severity) {
      Severity.bug => Container(
          width: 9, height: 9,
          decoration: const BoxDecoration(color: FluoColors.bug, shape: BoxShape.circle)),
      Severity.ux => Container(
          width: 9, height: 9,
          decoration: BoxDecoration(
              color: FluoColors.ux, borderRadius: BorderRadius.circular(2))),
      Severity.a11y => Transform.rotate(
          angle: 0.785398,
          child: Container(width: 8, height: 8, color: FluoColors.a11y)),
    };
  }
}

/// Lettered pin badge. [ringed] adds a dark outline so the badge stays
/// visible on top of any screenshot, light or dark (WCAG 1.4.11).
class PinBadge extends StatelessWidget {
  const PinBadge(this.text, this.color,
      {super.key, this.size = 20, this.fontSize = 12, this.ringed = false});
  final String text;
  final Color color;
  final double size;
  final double fontSize;
  final bool ringed;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: ringed ? Border.all(color: FluoColors.bg, width: 2) : null,
        ),
        child: Text(text, style: fs(fontSize, w: FontWeight.w600, c: FluoColors.onLime)),
      );
}

/// Pill filter chip, 44dp tall.
class FluoChip extends StatelessWidget {
  const FluoChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      selected: selected,
      radius: 22,
      builder: (_, _) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? context.accent.soft : null,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: selected ? context.accent.color : FluoColors.borderStrong),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (leading != null) ...[leading!, const SizedBox(width: 7)],
          Text(label,
              style: fs(14,
                  w: FontWeight.w500,
                  c: selected ? context.accent.text : FluoColors.fg)),
        ]),
      ),
    );
  }
}

/// Rounded surface card.
class FluoCard extends StatelessWidget {
  const FluoCard({super.key, required this.child, this.padding, this.radius = 14});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: FluoColors.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: FluoColors.border),
        ),
        child: child,
      );
}

/// Switch row: label + helper text + 44dp-tall hit area.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.help,
    required this.value,
    required this.onChanged,
    this.accent,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.enabled = true,
  });
  final String title;
  final String help;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Off: dimmed and not tappable (the setting does not apply right now).
  final bool enabled;
  final Color? accent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: enabled ? () => onChanged(!value) : null,
      toggled: value,
      label: '$title. $help',
      radius: 8,
      builder: (_, _) => Opacity(
        opacity: enabled ? 1 : 0.5,
        child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: padding,
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: fs(15, w: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(help, style: fs(13, c: FluoColors.fgMuted, h: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Track(on: value, accent: accent ?? context.accent.color),
          ]),
        ),
      ),
      ),
    );
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.on, required this.accent});
  final bool on;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        height: 26,
        padding: const EdgeInsets.all(3),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: on ? accent : FluoColors.surfaceHi,
          borderRadius: BorderRadius.circular(13),
          // Off track edge meets 3:1 against the card.
          border: Border.all(color: on ? accent : FluoColors.borderStrong),
        ),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? context.accent.onColor : FluoColors.fg,
          ),
        ),
      );
}

/// Labelled text field with the mock's 3:1 border. On focus the border takes
/// the accent colour, so the field shows one clear edge (the package adds a
/// soft ring around it). The keyboard's Done key closes the keyboard.
class FluoField extends StatefulWidget {
  const FluoField({
    super.key,
    required this.label,
    required this.initial,
    this.height = 44,
    this.fill = FluoColors.bg,
    this.fontSize = 15,
    this.onChanged,
    this.placeholder,
    this.autocorrect = true,
  });
  final String label;
  final String initial;
  final ValueChanged<String>? onChanged;
  final String? placeholder;
  final double height;
  final Color fill;
  final double fontSize;

  /// Off for names, where autocorrect rewrites words it does not know.
  final bool autocorrect;

  @override
  State<FluoField> createState() => _FluoFieldState();
}

class _FluoFieldState extends State<FluoField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          excludeSemantics: true,
          child: Text(widget.label, style: fs(13, w: FontWeight.w500, c: FluoColors.fgMuted)),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: widget.height,
          child: Semantics(
            label: widget.label,
            child: TextField(
              focusNode: _focus,
              initialValue: widget.initial,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _focus.unfocus(),
              autocorrect: widget.autocorrect,
              placeholder: widget.placeholder == null
                  ? null
                  : Text(widget.placeholder!, style: fs(widget.fontSize, c: FluoColors.fgMuted)),
              style: fs(widget.fontSize),
              crossAxisAlignment: CrossAxisAlignment.center,
              textAlignVertical: TextAlignVertical.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: widget.fill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused ? context.accent.color : FluoColors.borderStrong,
                  width: focused ? 2 : 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Header row: optional back/close, title block, trailing actions.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.big = false,
    this.leading,
    this.trailing = const [],
  });
  final String title;
  final String? subtitle;
  final bool big;
  final Widget? leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final titleW = Semantics(
      header: true,
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: big
            ? fs(28, w: FontWeight.w600, ls: -0.56)
            : fs(17, w: FontWeight.w600),
      ),
    );
    return Row(children: [
      if (leading != null) ...[leading!, const SizedBox(width: 10)],
      Expanded(
        child: subtitle == null
            ? titleW
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  titleW,
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: fs(13, c: FluoColors.fgMuted)),
                ],
              ),
      ),
      for (final t in trailing) ...[const SizedBox(width: 10), t],
    ]);
  }
}

/// Dark page with safe area and the mock's 20dp gutters.
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 24),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    // The system keyboard is not part of the layout by itself (Flutter only
    // reports its height), so a focused field under it stays hidden. Lift the
    // screen above it, and tell descendants the inset is handled so nothing
    // pads for it twice. With the keyboard up the bottom safe area is already
    // covered by the keyboard.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      color: FluoColors.bg,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: SafeArea(
            bottom: keyboard == 0,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

Widget backButton(BuildContext context, {String label = 'Back'}) =>
    FluoIconButton(
      icon: LucideIcons.chevronLeft,
      label: label,
      onPressed: () => Navigator.of(context).maybePop(),
    );
