import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waiting_room_app/geolocation_service.dart';
import 'package:waiting_room_app/local_queue_service.dart';
import 'package:waiting_room_app/queue_provider.dart';

class FakeGeolocationService extends Fake implements GeolocationService {
  @override
  Future<Position?> getCurrentPosition() async => null;
}

class FakeSupabaseClient extends Fake implements SupabaseClient {
  final List<dynamic> upsertedValues = [];

  @override
  SupabaseQueryBuilder from(String table) {
    return FakeSupabaseQueryBuilder(this, table);
  }
}

class FakeSupabaseQueryBuilder extends Fake implements SupabaseQueryBuilder {
  final FakeSupabaseClient client;
  final String table;

  FakeSupabaseQueryBuilder(this.client, this.table);

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> upsert(
    Object values, {
    String? onConflict,
    bool ignoreDuplicates = false,
    bool defaultToNull = true,
  }) {
    client.upsertedValues.add(values);
    return FakePostgrestFilterBuilder([
      {
        'id': (values as Map)['id'] ?? 'test-id-1',
        'name': values['name'],
        'created_at': values['created_at'] ?? DateTime.now().toIso8601String(),
      }
    ]);
  }
}

class FakePostgrestFilterBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  final List<Map<String, dynamic>> result;

  FakePostgrestFilterBuilder(this.result);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) {
    return Future.value(result).then(onValue, onError: onError);
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await LocalQueueService(inMemory: true).database;
    await db.delete(LocalQueueService.tableName);
  });

  test('addClient saves locally and triggers remote sync', () async {
    final fakeClient = FakeSupabaseClient();
    final provider = QueueProvider(
      supabase: fakeClient,
      geoService: FakeGeolocationService(),
      localDb: LocalQueueService(inMemory: true),
    );

    await provider.addClient("Alice");
    await Future.delayed(const Duration(milliseconds: 100));

    expect(provider.clients.length, 1);
    expect(provider.clients.first['name'], 'Alice');
    expect(fakeClient.upsertedValues.length, 1);
    expect((fakeClient.upsertedValues.first as Map)['name'], 'Alice');
  });
}
