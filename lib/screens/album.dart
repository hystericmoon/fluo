import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../data/fake_data.dart';
import '../theme/tokens.dart';
import '../ui/fake_shot.dart';
import '../ui/kit.dart';
import 'editor.dart';
import 'export.dart';

enum _Mode { grid, flow }

/// Album: Grid and Flow order views with severity filters.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.title});
  final String title;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  _Mode _mode = _Mode.flow;
  Severity? _filter; // null = All

  @override
  Widget build(BuildContext context) {
    final flow = _mode == _Mode.flow;
    final shots = [
      for (var i = 0; i < fakeShots.length; i++)
        if (_filter == null || fakeShots[i].pins.contains(_filter)) (i, fakeShots[i]),
    ];
    return ScreenFrame(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: widget.title,
            leading: backButton(context, label: 'Back to albums'),
            trailing: [
              FluoButton(
                label: 'Export',
                icon: LucideIcons.upload,
                kind: BtnKind.primary,
                onPressed: () => Navigator.of(context).push(fluoRoute(const ExportScreen())),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Segmented(
            flow: flow,
            onChanged: (f) => setState(() => _mode = f ? _Mode.flow : _Mode.grid),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              FluoChip(
                  label: 'All 19', selected: _filter == null, onTap: () => setState(() => _filter = null)),
              for (final s in Severity.values) ...[
                const SizedBox(width: 8),
                FluoChip(
                  label: '${s.label} ${const {Severity.bug: 3, Severity.ux: 5, Severity.a11y: 2}[s]}',
                  leading: SeverityDot(s),
                  selected: _filter == s,
                  onTap: () => setState(() => _filter = _filter == s ? null : s),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: shots.isEmpty
                ? Center(
                    child: Text('No screens with this severity',
                        style: fs(14, c: FluoColors.fgMuted)))
                : GridView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 10,
                      mainAxisExtent: 190 + 6 + 18,
                    ),
                    itemCount: shots.length,
                    itemBuilder: (context, i) {
                      final (idx, shot) = shots[i];
                      return Pressable(
                        radius: 10,
                        label:
                            '${flow ? 'Screen ${idx + 1}: ' : ''}${shot.name}, ${shot.pins.isEmpty ? 'no pins' : shot.pins.map((p) => p.label).join(', ')}',
                        onTap: () => Navigator.of(context).push(fluoRoute(const EditorScreen())),
                        builder: (_, _) => ExcludeSemantics(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            TileShot(shot: shot, number: flow ? idx + 1 : null),
                            const SizedBox(height: 6),
                            Text(shot.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: fs(13, w: FontWeight.w500)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.flow, required this.onChanged});
  final bool flow;
  final ValueChanged<bool> onChanged;

  Widget _seg(String label, bool on, VoidCallback tap) => Expanded(
        child: Pressable(
          onTap: tap,
          selected: on,
          radius: 8,
          builder: (_, _) => Container(
            height: 44,
            alignment: Alignment.center,
            color: on ? FluoColors.lime : null,
            child: Text(label,
                style: fs(15, w: FontWeight.w500, c: on ? FluoColors.onLime : FluoColors.fg)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: FluoColors.borderStrong),
        ),
        child: Row(children: [
          _seg('Grid', !flow, () => onChanged(false)),
          _seg('Flow order', flow, () => onChanged(true)),
        ]),
      );
}
