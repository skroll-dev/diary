import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readAndDeleteFile(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  await file.delete();
  return bytes;
}
