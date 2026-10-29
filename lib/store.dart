import 'package:sqflite/sqflite.dart';

class MediaRecord {
  const MediaRecord({
    required this.id,
    required this.takenAt,
    this.modifiedAt = 0,
    this.width = 0,
    this.height = 0,
    required this.month,
    required this.type,
    required this.duration,
    required this.screenshot,
    required this.selfie,
    required this.live,
  });

  final String id;
  final int takenAt;
  final int modifiedAt;
  final int width;
  final int height;
  final String month;
  final int type; // 1=image, 2=video
  final int duration;
  final bool screenshot;
  final bool selfie;
  final bool live;

  factory MediaRecord.fromMap(Map<String, Object?> row) => MediaRecord(
    id: row['id'] as String,
    takenAt: row['taken_at'] as int,
    modifiedAt: row['modified_at'] as int,
    width: row['width'] as int,
    height: row['height'] as int,
    month: row['month'] as String,
    type: row['type'] as int,
    duration: row['duration'] as int,
    screenshot: row['screenshot'] == 1,
    selfie: row['selfie'] == 1,
    live: row['live'] == 1,
  );

  Map<String, Object?> toMap(int scanId) => {
    'id': id,
    'taken_at': takenAt,
    'modified_at': modifiedAt,
    'width': width,
    'height': height,
    'month': month,
    'type': type,
    'duration': duration,
    'screenshot': screenshot ? 1 : 0,
    'selfie': selfie ? 1 : 0,
    'live': live ? 1 : 0,
    'last_seen_at': scanId,
  };
}

class Scope {
  const Scope(this.key, this.label);
  final String key;
  final String label;

  static const all = Scope('all', '全部照片与视频');
  static const screenshots = Scope('category:screenshot', '截屏');
  static const selfies = Scope('category:selfie', '自拍');
  static const videos = Scope('category:video', '视频');
  static const live = Scope('category:live', '实况照片');

  static Scope month(String month) =>
      Scope('month:$month', month == 'unknown' ? '时间未知' : month);

  static Scope year(String year) => Scope('year:$year', year);

  (String, List<Object?>) get filter {
    if (key == 'all') return ('1=1', []);
    if (key.startsWith('month:')) {
      return ('m.month = ?', [key.substring(6)]);
    }
    if (key.startsWith('year:')) {
      return ('m.month LIKE ?', ['${key.substring(5)}-%']);
    }
    return switch (key) {
      'category:screenshot' => ('m.screenshot = 1', []),
      'category:selfie' => ('m.selfie = 1', []),
      'category:video' => ('m.type = 2', []),
      'category:live' => ('m.live = 1', []),
      _ => throw ArgumentError.value(key, 'key', 'Unknown scope'),
    };
  }
}

enum ReviewAction { delete, pending, keep, skip, restore }

class ReviewProgress {
  const ReviewProgress({
    required this.position,
    required this.total,
    required this.updatedAt,
  });

  final int position;
  final int total;
  final int updatedAt;
}

class MediaCounts {
  const MediaCounts({
    required this.total,
    required this.photos,
    required this.videos,
    required this.screenshots,
    required this.live,
  });

  final int total;
  final int photos;
  final int videos;
  final int screenshots;
  final int live;
}

class ActionSnapshot {
  const ActionSnapshot(
    this.mediaId,
    this.scopeKey,
    this.queue,
    this.kept,
    this.pending,
    this.anchor,
  );
  final String mediaId;
  final String scopeKey;
  final Map<String, Object?>? queue;
  final Map<String, Object?>? kept;
  final List<Map<String, Object?>> pending;
  final Map<String, Object?>? anchor;
}

class AppStore {
  AppStore(this.db);
  final Database db;

  static Future<AppStore> open({String? path}) async {
    final base = path == null ? await getDatabasesPath() : null;
    final db = await openDatabase(
      path ?? '$base/album_cleaner.db',
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE media_cache (
            id TEXT PRIMARY KEY, taken_at INTEGER NOT NULL, month TEXT NOT NULL,
            type INTEGER NOT NULL, duration INTEGER NOT NULL,
            screenshot INTEGER NOT NULL, selfie INTEGER NOT NULL,
            live INTEGER NOT NULL, last_seen_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL, width INTEGER NOT NULL,
            height INTEGER NOT NULL
          )''');
        await db.execute(
          'CREATE INDEX media_order ON media_cache(taken_at DESC, id DESC)',
        );
        await db.execute(
          'CREATE INDEX media_month ON media_cache(month, taken_at DESC, id DESC)',
        );
        await db.execute('''CREATE TABLE scope_progress (
          scope_key TEXT PRIMARY KEY, anchor_media_id TEXT, anchor_time INTEGER,
          updated_at INTEGER NOT NULL)''');
        await db.execute('''CREATE TABLE scope_decision (
          scope_key TEXT NOT NULL, media_id TEXT NOT NULL,
          decision TEXT NOT NULL CHECK(decision = 'undecided'),
          updated_at INTEGER NOT NULL, PRIMARY KEY(scope_key, media_id))''');
        await db.execute('''CREATE TABLE media_review (
          media_id TEXT PRIMARY KEY, decision TEXT NOT NULL CHECK(decision = 'kept'),
          updated_at INTEGER NOT NULL)''');
        await db.execute('''CREATE TABLE delete_queue (
          media_id TEXT PRIMARY KEY, marked_at INTEGER NOT NULL,
          status TEXT NOT NULL, last_error TEXT)''');
        await db.execute('''CREATE TABLE media_favorite (
          media_id TEXT PRIMARY KEY, created_at INTEGER NOT NULL)''');
        await db.execute('''CREATE TABLE media_similarity (
          media_id TEXT PRIMARY KEY, hash TEXT NOT NULL,
          modified_at INTEGER NOT NULL, width INTEGER NOT NULL,
          height INTEGER NOT NULL, algorithm_version INTEGER NOT NULL)''');
        await db.execute('''CREATE TABLE media_similarity_group (
          media_id TEXT PRIMARY KEY, group_order INTEGER NOT NULL,
          member_order INTEGER NOT NULL, algorithm_version INTEGER NOT NULL,
          max_distance INTEGER NOT NULL, generated_at INTEGER NOT NULL)''');
        await db.execute(
          '''CREATE TABLE app_settings (
          key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)''',
        );
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute('''CREATE TABLE media_favorite (
            media_id TEXT PRIMARY KEY, created_at INTEGER NOT NULL)''');
        }
        if (oldVersion < 3) {
          await db.execute('''CREATE TABLE media_similarity (
            media_id TEXT PRIMARY KEY, hash TEXT NOT NULL)''');
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE media_cache ADD COLUMN modified_at INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE media_cache ADD COLUMN width INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE media_cache ADD COLUMN height INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('DROP TABLE media_similarity');
          await db.execute('''CREATE TABLE media_similarity (
            media_id TEXT PRIMARY KEY, hash TEXT NOT NULL,
            modified_at INTEGER NOT NULL, width INTEGER NOT NULL,
            height INTEGER NOT NULL, algorithm_version INTEGER NOT NULL)''');
          await db.execute('''CREATE TABLE media_similarity_group (
            media_id TEXT PRIMARY KEY, group_order INTEGER NOT NULL,
            member_order INTEGER NOT NULL, algorithm_version INTEGER NOT NULL,
            max_distance INTEGER NOT NULL, generated_at INTEGER NOT NULL)''');
        }
      },
    );
    return AppStore(db);
  }

  Future<void> close() => db.close();

  Future<String?> setting(String key) async {
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) => db
      .insert('app_settings', {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});

  Future<void> upsertMediaPage(List<MediaRecord> media, int scanId) async {
    final batch = db.batch();
    for (final item in media) {
      batch.insert(
        'media_cache',
        item.toMap(scanId),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> finishScan(int scanId) async {
    await db.delete(
      'media_cache',
      where: 'last_seen_at != ?',
      whereArgs: [scanId],
    );
    await db.rawDelete(
      'DELETE FROM media_similarity WHERE media_id NOT IN (SELECT id FROM media_cache)',
    );
    await db.rawDelete(
      'DELETE FROM media_similarity_group WHERE media_id NOT IN (SELECT id FROM media_cache)',
    );
  }

  Future<List<MediaRecord>> photoRecords() async {
    final rows = await db.query(
      'media_cache',
      where: 'type = 1',
      orderBy: 'taken_at DESC, id DESC',
    );
    return rows.map(MediaRecord.fromMap).toList();
  }

  Future<Map<String, String>> similarityHashes({
    required int algorithmVersion,
  }) async {
    final rows = await db.rawQuery(
      '''SELECT s.media_id, s.hash FROM media_similarity s
      INNER JOIN media_cache m ON m.id = s.media_id
      WHERE s.algorithm_version = ? AND s.modified_at = m.modified_at
      AND s.width = m.width AND s.height = m.height''',
      [algorithmVersion],
    );
    return {
      for (final row in rows) row['media_id'] as String: row['hash'] as String,
    };
  }

  Future<void> saveSimilarityHash(
    MediaRecord media,
    String hash, {
    required int algorithmVersion,
  }) => db
      .insert('media_similarity', {
        'media_id': media.id,
        'hash': hash,
        'modified_at': media.modifiedAt,
        'width': media.width,
        'height': media.height,
        'algorithm_version': algorithmVersion,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});

  String _similarityGroupSettingKey(int algorithmVersion, int maxDistance) =>
      'similarity_groups:$algorithmVersion:$maxDistance';

  Future<List<List<String>>?> similarityGroups({
    required int algorithmVersion,
    required int maxDistance,
  }) async {
    final key = _similarityGroupSettingKey(algorithmVersion, maxDistance);
    if (await setting(key) == null) return null;
    final rows = await db.rawQuery(
      '''SELECT g.group_order, g.member_order, g.media_id
      FROM media_similarity_group g
      INNER JOIN media_cache m ON m.id = g.media_id
      WHERE g.algorithm_version = ? AND g.max_distance = ?
      ORDER BY g.group_order, g.member_order''',
      [algorithmVersion, maxDistance],
    );
    final groups = <int, List<String>>{};
    for (final row in rows) {
      groups
          .putIfAbsent(row['group_order'] as int, () => [])
          .add(row['media_id'] as String);
    }
    return groups.values.where((group) => group.length > 1).toList();
  }

  Future<int?> similarityGeneratedAt({
    required int algorithmVersion,
    required int maxDistance,
  }) async {
    final value = await setting(
      _similarityGroupSettingKey(algorithmVersion, maxDistance),
    );
    return value == null ? null : int.tryParse(value);
  }

  Future<void> clearSimilarityAnalysis() => db.transaction((txn) async {
    await txn.delete('media_similarity');
    await txn.delete('media_similarity_group');
    await txn.delete(
      'app_settings',
      where: 'key LIKE ?',
      whereArgs: ['similarity_groups:%'],
    );
  });

  Future<void> replaceSimilarityGroups(
    List<List<String>> groups, {
    required int algorithmVersion,
    required int maxDistance,
  }) => db.transaction((txn) async {
    await txn.delete('media_similarity_group');
    await txn.delete(
      'app_settings',
      where: 'key LIKE ?',
      whereArgs: ['similarity_groups:%'],
    );
    final generatedAt = DateTime.now().millisecondsSinceEpoch;
    final batch = txn.batch();
    for (var groupOrder = 0; groupOrder < groups.length; groupOrder++) {
      for (
        var memberOrder = 0;
        memberOrder < groups[groupOrder].length;
        memberOrder++
      ) {
        batch.insert('media_similarity_group', {
          'media_id': groups[groupOrder][memberOrder],
          'group_order': groupOrder,
          'member_order': memberOrder,
          'algorithm_version': algorithmVersion,
          'max_distance': maxDistance,
          'generated_at': generatedAt,
        });
      }
    }
    await batch.commit(noResult: true);
    await txn.insert('app_settings', {
      'key': _similarityGroupSettingKey(algorithmVersion, maxDistance),
      'value': generatedAt.toString(),
      'updated_at': generatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  Future<List<(String, int)>> months() async {
    final rows = await db.rawQuery('''SELECT month, COUNT(*) AS total
      FROM media_cache GROUP BY month ORDER BY month DESC''');
    return rows
        .map((row) => (row['month'] as String, row['total'] as int))
        .toList();
  }

  Future<MediaCounts> mediaCounts() async {
    final rows = await db.rawQuery('''SELECT
      COUNT(*) AS total,
      SUM(CASE WHEN type = 1 THEN 1 ELSE 0 END) AS photos,
      SUM(CASE WHEN type = 2 THEN 1 ELSE 0 END) AS videos,
      SUM(CASE WHEN screenshot = 1 THEN 1 ELSE 0 END) AS screenshots,
      SUM(CASE WHEN live = 1 THEN 1 ELSE 0 END) AS live
      FROM media_cache''');
    final row = rows.first;
    int value(String key) => (row[key] as int?) ?? 0;
    return MediaCounts(
      total: value('total'),
      photos: value('photos'),
      videos: value('videos'),
      screenshots: value('screenshots'),
      live: value('live'),
    );
  }

  Future<ReviewProgress?> reviewProgress(Scope scope) async {
    final actionAt = await setting('last_action_at:${scope.key}');
    final anchorId = await anchor(scope);
    if (actionAt == null || anchorId == null) return null;
    return ReviewProgress(
      position: await positionOf(scope, anchorId, unreviewedOnly: true),
      total: await count(scope, unreviewedOnly: true),
      updatedAt: int.parse(actionAt),
    );
  }

  (String, List<Object?>) _decisionFilter(
    Scope scope, {
    required bool pendingOnly,
    required bool unreviewedOnly,
  }) {
    if (pendingOnly) {
      return (
        '''AND EXISTS (SELECT 1 FROM scope_decision d
          WHERE d.scope_key = ? AND d.media_id = m.id)
        AND NOT EXISTS (SELECT 1 FROM delete_queue q WHERE q.media_id = m.id)
        AND NOT EXISTS (SELECT 1 FROM media_review r WHERE r.media_id = m.id)''',
        [scope.key],
      );
    }
    if (unreviewedOnly) {
      return (
        '''AND NOT EXISTS (SELECT 1 FROM delete_queue q WHERE q.media_id = m.id)
        AND NOT EXISTS (SELECT 1 FROM media_review r WHERE r.media_id = m.id)
        AND NOT EXISTS (SELECT 1 FROM scope_decision d
          WHERE d.scope_key = ? AND d.media_id = m.id)''',
        [scope.key],
      );
    }
    return (
      'AND NOT EXISTS (SELECT 1 FROM delete_queue q WHERE q.media_id = m.id)',
      const [],
    );
  }

  Future<int> count(
    Scope scope, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async {
    final (filter, args) = scope.filter;
    final (decision, decisionArgs) = _decisionFilter(
      scope,
      pendingOnly: pendingOnly,
      unreviewedOnly: unreviewedOnly,
    );
    final rows = await db.rawQuery(
      '''SELECT COUNT(*) AS total FROM media_cache m
      WHERE $filter $decision''',
      [...args, ...decisionArgs],
    );
    return rows.first['total'] as int;
  }

  Future<MediaRecord?> at(
    Scope scope,
    int index, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async {
    final (filter, args) = scope.filter;
    final (decision, decisionArgs) = _decisionFilter(
      scope,
      pendingOnly: pendingOnly,
      unreviewedOnly: unreviewedOnly,
    );
    final rows = await db.rawQuery(
      '''SELECT m.* FROM media_cache m
      WHERE $filter $decision ORDER BY m.taken_at DESC, m.id DESC LIMIT 1 OFFSET ?''',
      [...args, ...decisionArgs, index],
    );
    return rows.isEmpty ? null : MediaRecord.fromMap(rows.first);
  }

  Future<List<MediaRecord>> list(
    Scope scope, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async {
    final (filter, args) = scope.filter;
    final (decision, decisionArgs) = _decisionFilter(
      scope,
      pendingOnly: pendingOnly,
      unreviewedOnly: unreviewedOnly,
    );
    final rows = await db.rawQuery(
      '''SELECT m.* FROM media_cache m
      WHERE $filter $decision ORDER BY m.taken_at DESC, m.id DESC''',
      [...args, ...decisionArgs],
    );
    return rows.map(MediaRecord.fromMap).toList();
  }

  Future<int> positionOf(
    Scope scope,
    String id, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async {
    final media = await db.query(
      'media_cache',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (media.isEmpty) return 0;
    final (filter, args) = scope.filter;
    final time = media.first['taken_at'] as int;
    final (decision, decisionArgs) = _decisionFilter(
      scope,
      pendingOnly: pendingOnly,
      unreviewedOnly: unreviewedOnly,
    );
    final rows = await db.rawQuery(
      '''SELECT COUNT(*) AS total FROM media_cache m
      WHERE $filter $decision AND (m.taken_at > ? OR (m.taken_at = ? AND m.id > ?))''',
      [...args, ...decisionArgs, time, time, id],
    );
    return rows.first['total'] as int;
  }

  Future<Set<String>> reviewedIds(Scope scope) async {
    final rows = await db.rawQuery(
      '''SELECT media_id FROM delete_queue
      UNION SELECT media_id FROM media_review
      UNION SELECT media_id FROM scope_decision WHERE scope_key = ?''',
      [scope.key],
    );
    return rows.map((row) => row['media_id'] as String).toSet();
  }

  Future<String?> anchor(Scope scope) async {
    final rows = await db.query(
      'scope_progress',
      where: 'scope_key = ?',
      whereArgs: [scope.key],
    );
    return rows.isEmpty ? null : rows.first['anchor_media_id'] as String?;
  }

  Future<void> saveAnchor(Scope scope, MediaRecord media) => db
      .insert('scope_progress', {
        'scope_key': scope.key,
        'anchor_media_id': media.id,
        'anchor_time': media.takenAt,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});

  Future<String?> status(Scope scope, String id) async {
    if ((await db.query(
      'delete_queue',
      where: 'media_id = ?',
      whereArgs: [id],
    )).isNotEmpty) {
      return 'delete';
    }
    if ((await db.query(
      'media_review',
      where: 'media_id = ?',
      whereArgs: [id],
    )).isNotEmpty) {
      return 'kept';
    }
    if ((await db.query(
      'scope_decision',
      where: 'scope_key = ? AND media_id = ?',
      whereArgs: [scope.key, id],
    )).isNotEmpty) {
      return 'pending';
    }
    return null;
  }

  Future<ActionSnapshot?> act(
    Scope scope,
    MediaRecord media,
    ReviewAction action,
  ) async {
    if (action == ReviewAction.skip) {
      await saveAnchor(scope, media);
      await setSetting(
        'last_action_at:${scope.key}',
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
      return null;
    }
    return db.transaction((txn) async {
      final queue = await txn.query(
        'delete_queue',
        where: 'media_id = ?',
        whereArgs: [media.id],
      );
      final kept = await txn.query(
        'media_review',
        where: 'media_id = ?',
        whereArgs: [media.id],
      );
      final pending = await txn.query(
        'scope_decision',
        where: 'media_id = ?',
        whereArgs: [media.id],
      );
      final anchor = await txn.query(
        'scope_progress',
        where: 'scope_key = ?',
        whereArgs: [scope.key],
      );
      final snapshot = ActionSnapshot(
        media.id,
        scope.key,
        queue.isEmpty ? null : queue.first,
        kept.isEmpty ? null : kept.first,
        pending,
        anchor.isEmpty ? null : anchor.first,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      if (action == ReviewAction.delete) {
        await txn.delete(
          'media_review',
          where: 'media_id = ?',
          whereArgs: [media.id],
        );
        await txn.delete(
          'scope_decision',
          where: 'media_id = ?',
          whereArgs: [media.id],
        );
        await txn.insert('delete_queue', {
          'media_id': media.id,
          'marked_at': now,
          'status': 'queued',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else if (action == ReviewAction.restore) {
        await txn.delete(
          'scope_decision',
          where: 'media_id = ?',
          whereArgs: [media.id],
        );
      } else {
        await txn.delete(
          'delete_queue',
          where: 'media_id = ?',
          whereArgs: [media.id],
        );
        await txn.delete(
          'media_review',
          where: 'media_id = ?',
          whereArgs: [media.id],
        );
        if (action == ReviewAction.keep) {
          await txn.delete(
            'scope_decision',
            where: 'media_id = ?',
            whereArgs: [media.id],
          );
          await txn.insert('media_review', {
            'media_id': media.id,
            'decision': 'kept',
            'updated_at': now,
          });
        } else {
          await txn.insert('scope_decision', {
            'scope_key': scope.key,
            'media_id': media.id,
            'decision': 'undecided',
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await txn.insert('scope_progress', {
        'scope_key': scope.key,
        'anchor_media_id': media.id,
        'anchor_time': media.takenAt,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'key': 'last_action_at:${scope.key}',
        'value': now.toString(),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return snapshot;
    });
  }

  Future<void> undo(ActionSnapshot snapshot) => db.transaction((txn) async {
    await txn.delete(
      'delete_queue',
      where: 'media_id = ?',
      whereArgs: [snapshot.mediaId],
    );
    await txn.delete(
      'media_review',
      where: 'media_id = ?',
      whereArgs: [snapshot.mediaId],
    );
    await txn.delete(
      'scope_decision',
      where: 'media_id = ?',
      whereArgs: [snapshot.mediaId],
    );
    if (snapshot.queue != null) {
      await txn.insert('delete_queue', snapshot.queue!);
    }
    if (snapshot.kept != null) await txn.insert('media_review', snapshot.kept!);
    for (final row in snapshot.pending) {
      await txn.insert('scope_decision', row);
    }
    await txn.delete(
      'scope_progress',
      where: 'scope_key = ?',
      whereArgs: [snapshot.scopeKey],
    );
    if (snapshot.anchor != null) {
      await txn.insert('scope_progress', snapshot.anchor!);
    }
  });

  Future<List<Map<String, Object?>>> queue() =>
      db.query('delete_queue', orderBy: 'marked_at ASC');

  Future<bool> isFavorite(String id) async => (await db.query(
    'media_favorite',
    where: 'media_id = ?',
    whereArgs: [id],
    limit: 1,
  )).isNotEmpty;

  Future<void> setFavorite(String id, bool favorite) async {
    if (!favorite) {
      await db.delete('media_favorite', where: 'media_id = ?', whereArgs: [id]);
      return;
    }
    await db.insert('media_favorite', {
      'media_id': id,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFromQueue(String id) => db
      .delete('delete_queue', where: 'media_id = ?', whereArgs: [id])
      .then((_) {});

  Future<void> setQueueStatus(String id, String status, {String? error}) => db
      .update(
        'delete_queue',
        {'status': status, 'last_error': error},
        where: 'media_id = ?',
        whereArgs: [id],
      )
      .then((_) {});

  Future<void> clearRecords() => db.transaction((txn) async {
    for (final table in [
      'scope_progress',
      'scope_decision',
      'media_review',
      'delete_queue',
      'media_favorite',
    ]) {
      await txn.delete(table);
    }
    await txn.delete(
      'app_settings',
      where: 'key LIKE ?',
      whereArgs: ['last_action_at:%'],
    );
  });
}
