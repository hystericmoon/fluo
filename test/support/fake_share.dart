import 'package:fluo/export/model.dart';
import 'package:fluo/export/share_service.dart';

/// Records what would have gone to the system share sheet.
class FakeShare implements ShareService {
  final shared = <ExportResult>[];
  Object? failWith;

  @override
  Future<void> share(ExportResult result) async {
    if (failWith != null) throw failWith!;
    shared.add(result);
  }
}
