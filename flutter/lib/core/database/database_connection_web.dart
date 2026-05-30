import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

Future<QueryExecutor> openDatabaseConnection() async {
  final result = await WasmDatabase.open(
    databaseName: 'mathias',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.dart.js'),
  );
  return result.resolvedExecutor;
}
