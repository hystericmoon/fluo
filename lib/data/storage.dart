import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'file_store.dart';
import 'repository.dart';

/// Opens the repository in the app's private documents folder.
/// Everything stays on the device: `<docs>/fluo/fluo.db` and `<docs>/fluo/originals/`.
Future<FluoRepo> openAppRepo() async {
  final docs = await getApplicationDocumentsDirectory();
  final root = Directory(p.join(docs.path, 'fluo'));
  await root.create(recursive: true);
  return FluoRepo(FluoDb.open(p.join(root.path, 'fluo.db')), FileStore(root));
}
