import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../data/fake_data.dart';
import '../theme/tokens.dart';
import 'kit.dart';

const _paper = Color(0xFFF4F4F5);
const _ink = Color(0xFF27272A);
const _line = Color(0xFFD4D4D8);
const _block = Color(0xFFE4E4E7);
const _blue = Color(0xFF2563EB);

Widget _bar(double? w, double h, Color c, [double? r]) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(r ?? h / 2)),
    );

class _Row extends StatelessWidget {
  const _Row(this.w1, this.w2, {this.thumb = 56, this.small = false});
  final double w1, w2, thumb;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final h1 = small ? 7.0 : 9.0, h2 = small ? 6.0 : 8.0;
    return SizedBox(
      height: thumb,
      child: Row(children: [
        Container(
            width: thumb,
            height: thumb,
            decoration: BoxDecoration(color: _block, borderRadius: BorderRadius.circular(small ? 8 : 10))),
        SizedBox(width: small ? 8 : 10),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            FractionallySizedBox(widthFactor: w1, child: _bar(null, h1, _ink)),
            SizedBox(height: small ? 6 : 7),
            FractionallySizedBox(widthFactor: w2, child: _bar(null, h2, _line)),
          ]),
        ),
        SizedBox(width: small ? 8 : 10),
        _bar(small ? 26 : 34, h1, _ink),
      ]),
    );
  }
}

/// Triage card, 270x500: a cart screen.
class TriageShot extends StatelessWidget {
  const TriageShot({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      height: 500,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF3F3F46)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 20, height: 20, decoration: const BoxDecoration(color: _line, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Text('Your cart', style: fs(16, w: FontWeight.w600, c: const Color(0xFF18181B))),
        ]),
        const SizedBox(height: 14),
        const _Row(0.8, 0.5),
        const SizedBox(height: 10),
        const _Row(0.7, 0.4),
        const SizedBox(height: 10),
        const _Row(0.76, 0.46),
        const SizedBox(height: 14),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _line)),
          child: _bar(90, 8, _line),
        ),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_bar(56, 8, _line), _bar(34, 8, _line)]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_bar(48, 8, _line), _bar(34, 8, _line)]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_bar(44, 10, _ink), _bar(40, 10, _ink)]),
        const Spacer(),
        Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(12)),
          child: Text('Pay now', style: fs(15, w: FontWeight.w600, c: const Color(0xFFFFFFFF))),
        ),
      ]),
    );
  }
}

/// Album grid tile, 190dp tall, with optional flow number and pins.
class TileShot extends StatelessWidget {
  const TileShot({super.key, required this.shot, this.number});
  final ShotInfo shot;
  final int? number;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3F3F46)),
      ),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FractionallySizedBox(widthFactor: 0.5, child: _bar(null, 7, _ink)),
            const SizedBox(height: 10),
            Container(height: 44, decoration: BoxDecoration(color: _block, borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 10),
            FractionallySizedBox(widthFactor: 0.8, child: _bar(null, 6, _line)),
            const SizedBox(height: 6),
            FractionallySizedBox(widthFactor: 0.6, child: _bar(null, 6, _line)),
          ]),
        ),
        Positioned(left: 8, right: 8, bottom: 8, child: _bar(null, 20, shot.button, 6)),
        if (number != null)
          Positioned(left: 6, top: 6, child: PinBadge('$number', FluoColors.lime, size: 24)),
        Positioned(
          right: 6,
          bottom: 34,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final p in shot.pins) Padding(
              padding: const EdgeInsets.only(left: 3),
              child: PinBadge(p.letter, p.color),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Editor canvas shot, 216x384, with a pin pair, a box and a redaction.
class EditorShot extends StatelessWidget {
  const EditorShot({super.key});

  @override
  Widget build(BuildContext context) {
    Widget at(double l, double t, Widget c, {double? r, double? w}) =>
        Positioned(left: l, top: t, right: r, width: w, child: c);
    return Container(
      width: 216,
      height: 384,
      decoration: BoxDecoration(color: _paper, borderRadius: BorderRadius.circular(12)),
      child: Stack(clipBehavior: Clip.none, children: [
        at(12, 12, Text('Your cart', style: fs(12, w: FontWeight.w600, c: const Color(0xFF18181B)))),
        at(10, 34, Container(width: 104, height: 18, decoration: BoxDecoration(color: const Color(0xFF000000), borderRadius: BorderRadius.circular(3)))),
        at(12, 62, const Column(children: [
          _Row(0.75, 0.45, thumb: 36, small: true),
          SizedBox(height: 8),
          _Row(0.65, 0.40, thumb: 36, small: true),
          SizedBox(height: 8),
          _Row(0.70, 0.42, thumb: 36, small: true),
        ]), r: 12),
        at(12, 196, Container(
          height: 26,
          decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(8), border: Border.all(color: _line)),
        ), r: 12),
        at(12, 236, Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_bar(44, 6, _line), _bar(28, 6, _line)]),
          const SizedBox(height: 9),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_bar(38, 6, _line), _bar(28, 6, _line)]),
          const SizedBox(height: 9),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_bar(34, 8, _ink), _bar(32, 8, _ink)]),
        ]), r: 12),
        Positioned(
          left: 12, right: 12, bottom: 14,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(10)),
            child: Text('Pay now', style: fs(12, w: FontWeight.w600, c: const Color(0xFFFFFFFF))),
          ),
        ),
        // Annotations: box, pin 2, pin 1.
        at(6, 322, Container(
          width: 204, height: 52,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: FluoColors.bug, width: 2)),
        )),
        at(170, 112, const PinBadge('2', FluoColors.ux, size: 24, fontSize: 13)),
        at(166, 260, Container(
          decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: [
            // Later shadows paint on top: outer dark ring first, paper ring over it.
            BoxShadow(color: Color(0xFF18181B), spreadRadius: 4),
            BoxShadow(color: _paper, spreadRadius: 2),
          ]),
          child: const PinBadge('1', FluoColors.bug, size: 24, fontSize: 13),
        )),
      ]),
    );
  }
}
