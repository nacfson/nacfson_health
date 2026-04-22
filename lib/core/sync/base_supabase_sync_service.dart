import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase 동기화의 테이블별 공통 프로토콜.
///
/// - **Push**: `upsert(onConflict: 'uuid')` — sync_status 는 Supabase 에 저장하지 않고
///   `is_deleted` 플래그만 서버 측에 남긴다.
/// - **Pull**: `is_deleted = false` 만 반환하며 `updated_at > since` 로 증분 조회.
///   RLS 가 현재 사용자 데이터만 반환하므로 별도 user_id 필터는 없다.
///
/// 도메인 서브클래스는 세 가지 훅만 제공한다:
/// - [tableName]           : Supabase 테이블 이름
/// - [rowFromEntity]       : 엔티티 → upsert row map (공통 필드 `uuid`/`user_id`/
///                            `updated_at`/`is_deleted` 포함 전체 payload)
/// - [rowToEntity]         : Supabase row → 엔티티 (syncStatus 는 synced 고정)
abstract class BaseSupabaseSyncService<T> {
  SupabaseClient get _client => Supabase.instance.client;

  String get tableName;

  Map<String, dynamic> rowFromEntity(T entity, String userId);

  T rowToEntity(Map<String, dynamic> row);

  Future<void> batchPush(List<T> items) async {
    if (items.isEmpty) return;
    final userId = _client.auth.currentUser!.id;
    final rows = items.map((e) => rowFromEntity(e, userId)).toList();
    await _client.from(tableName).upsert(rows, onConflict: 'uuid');
  }

  Future<List<T>> readDelta({DateTime? since}) async {
    var query = _client.from(tableName).select().eq('is_deleted', false);
    final rows = since != null
        ? await query.gt('updated_at', since.toUtc().toIso8601String())
        : await query;
    return (rows as List)
        .map((r) => rowToEntity(r as Map<String, dynamic>))
        .toList();
  }
}
