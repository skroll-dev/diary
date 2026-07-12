import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database_connection_web.dart'
    if (dart.library.io) 'database_connection_native.dart';

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
  // JSON arrays stored as strings
  TextColumn get followUpQuestions =>
      text().withDefault(const Constant('[]'))();
  TextColumn get topics => text().withDefault(const Constant('[]'))();
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

class RawTranscripts extends Table {
  TextColumn get id => text()();
  TextColumn get entryId => text().references(Entries, #id)();
  TextColumn get content => text()(); // raw speech-to-text, never shown
  TextColumn get normalizedContent => text().withDefault(const Constant(''))();
  TextColumn get reason =>
      text().withDefault(const Constant('initial'))(); // initial | followUp:... | continuation
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Entries, RawTranscripts])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(LazyDatabase(() => openDatabaseConnection()));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.database.customStatement(
                "ALTER TABLE entries ADD COLUMN follow_up_questions TEXT NOT NULL DEFAULT '[]'");
            await m.database.customStatement(
                "ALTER TABLE entries ADD COLUMN topics TEXT NOT NULL DEFAULT '[]'");
            await m.database.customStatement(
                "ALTER TABLE raw_transcripts ADD COLUMN normalized_content TEXT NOT NULL DEFAULT ''");
            await m.database.customStatement(
                "ALTER TABLE raw_transcripts ADD COLUMN reason TEXT NOT NULL DEFAULT 'initial'");
          }
          if (from < 3) {
            await m.database.customStatement(
                "ALTER TABLE entries ADD COLUMN tags TEXT NOT NULL DEFAULT '[]'");
          }
        },
      );
}

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}
