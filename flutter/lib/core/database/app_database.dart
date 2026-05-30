import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_database.g.dart';

class Entries extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get date => text()(); // YYYY-MM-DD
  TextColumn get bodyMarkdown => text()();
  TextColumn get mood => text().withDefault(const Constant('neutral'))();
  RealColumn get moodScore => real().withDefault(const Constant(0.0))();
  IntColumn get durationSeconds => integer()();
  TextColumn get language => text().withDefault(const Constant('de'))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class RawTranscripts extends Table {
  TextColumn get id => text()();
  TextColumn get entryId => text().references(Entries, #id)();
  TextColumn get content => text()();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Entries, RawTranscripts])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'mathias.db'));
    return NativeDatabase.createInBackground(file);
  });
}

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}
