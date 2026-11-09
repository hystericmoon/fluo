import 'package:share_plus/share_plus.dart';

import 'model.dart';

/// Hands an export to the system share sheet. Nothing leaves the phone until
/// the person picks where it goes.
abstract class ShareService {
  Future<void> share(ExportResult result);
}

class SharePlusShareService implements ShareService {
  const SharePlusShareService();

  @override
  Future<void> share(ExportResult r) async {
    await SharePlus.instance.share(ShareParams(
      files: [for (final f in r.files) XFile(f.path, mimeType: f.mime, name: f.name)],
      fileNameOverrides: [for (final f in r.files) f.name],
      text: r.text,
      subject: r.subject,
    ));
  }
}
