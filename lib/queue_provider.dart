import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'geolocation_service.dart';
import 'local_queue_service.dart';

class QueueProvider extends ChangeNotifier {
  final SupabaseClient? _supabase;
  final LocalQueueService _localDb;
  GeolocationService geoService;
  RealtimeChannel? _subscription;

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> get clients => _clients;

  QueueProvider({
    GeolocationService? geoService,
    LocalQueueService? localDb,
    SupabaseClient? supabase,
  })  : geoService = geoService ?? GeolocationService(),
        _localDb = localDb ?? LocalQueueService(),
        _supabase = supabase ?? _resolveDefaultSupabase() {
    initialize();
  }

  static SupabaseClient? _resolveDefaultSupabase() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize() async {
    await _loadQueue();
  }

  Future<void> _loadQueue() async {
    // 1. Load from local DB immediately (offline support)
    try {
      _clients = List<Map<String, dynamic>>.from(await _localDb.getClients());
      notifyListeners();
    } catch (e) {
      debugPrint('Local DB load error: $e');
    }

    // 2. Fetch existing clients from Supabase so users appear immediately
    await _fetchRemoteClients();

    // 3. Sync unsynced records to Supabase
    await _syncLocalToRemote();

    // 4. Subscribe to real-time updates
    _setupRealtimeSubscription();
  }

  Future<void> _fetchRemoteClients() async {
    if (_supabase == null) return;
    try {
      final response = await _supabase
          .from('clients')
          .select()
          .order('created_at', ascending: true);

      final List<Map<String, dynamic>> remoteList = [];
      for (var record in response) {
        final clientMap = {
          'id': record['id'].toString(),
          'name': record['name'] as String? ?? '',
          'lat': record['lat'] is num ? (record['lat'] as num).toDouble() : null,
          'lng': record['lng'] is num ? (record['lng'] as num).toDouble() : null,
          'created_at':
              record['created_at']?.toString() ?? DateTime.now().toIso8601String(),
          'is_synced': 1,
        };
        remoteList.add(clientMap);
        await _localDb.insertClientLocally(clientMap);
      }
      _clients = remoteList;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching remote clients: $e');
    }
  }

  bool _isSyncing = false;

  Future<void> _syncLocalToRemote() async {
    if (_supabase == null || _isSyncing) return;
    _isSyncing = true;

    try {
      final unsynced = await _localDb.getUnsyncedClients();
      for (var client in unsynced) {
        try {
          final remoteClient = Map<String, dynamic>.from(client)
            ..remove('is_synced');

          try {
            await _supabase.from('clients').upsert(remoteClient);
          } catch (supabaseError) {
            final errorStr = supabaseError.toString();
            // Handle schema variations (e.g. integer primary key, missing lat/lng columns)
            if (errorStr.contains('PGRST204') ||
                errorStr.contains('22P02') ||
                errorStr.contains('bigint') ||
                errorStr.contains('column')) {
              final payload = <String, dynamic>{
                'name': client['name'],
              };
              if (int.tryParse(client['id'].toString()) != null) {
                payload['id'] = int.parse(client['id'].toString());
              }
              final inserted =
                  await _supabase.from('clients').insert(payload).select();
              if (inserted.isNotEmpty &&
                  int.tryParse(client['id'].toString()) == null) {
                final newId = inserted.first['id'].toString();
                await _localDb.deleteClientLocally(client['id'].toString());
                final updatedClient = Map<String, dynamic>.from(client)
                  ..['id'] = newId
                  ..['is_synced'] = 1;
                await _localDb.insertClientLocally(updatedClient);
                final idx = _clients.indexWhere(
                    (c) => c['id'].toString() == client['id'].toString());
                if (idx != -1) {
                  _clients[idx] = updatedClient;
                }
              }
            } else {
              rethrow;
            }
          }

          await _localDb.markClientAsSynced(client['id'] as String);
        } catch (e) {
          debugPrint('Sync failed for ${client['id']}: $e');
        }
      }

      // Refresh UI if any sync succeeded
      _clients = List<Map<String, dynamic>>.from(await _localDb.getClients());
      notifyListeners();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> addClient(String name) async {
    if (name.trim().isEmpty) return;

    Position? position;
    try {
      position = await geoService.getCurrentPosition();
    } catch (e) {
      debugPrint('Location capture skipped/failed: $e');
      position = null;
    }

    final newClient = {
      'id': const Uuid().v4(),
      'name': name.trim(),
      'lat': position?.latitude,
      'lng': position?.longitude,
      'created_at': DateTime.now().toIso8601String(),
      'is_synced': 0,
    };

    // Save locally immediately
    await _localDb.insertClientLocally(newClient);

    // Update UI instantly
    _clients.add(newClient);
    _clients.sort((a, b) =>
        (a['created_at'] as String).compareTo(b['created_at'] as String));
    notifyListeners();

    // Attempt sync (non-blocking for UX)
    unawaited(_syncLocalToRemote());
  }

  void _setupRealtimeSubscription() {
    if (_supabase == null) return;

    try {
      _subscription = _supabase
          .channel('public:clients')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'clients',
            callback: (payload) async {
              final newRecord = Map<String, dynamic>.from(payload.newRecord);
              newRecord['is_synced'] = 1;
              newRecord['id'] = newRecord['id'].toString();
              await _localDb.insertClientLocally(newRecord);
              if (!_clients.any((client) =>
                  client['id'].toString() == newRecord['id'].toString())) {
                _clients.add(newRecord);
                _clients.sort((a, b) => (a['created_at'] as String)
                    .compareTo(b['created_at'] as String));
                notifyListeners();
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'clients',
            callback: (payload) async {
              final deletedId = payload.oldRecord['id']?.toString();
              if (deletedId != null) {
                await _localDb.deleteClientLocally(deletedId);
                _clients.removeWhere(
                    (client) => client['id'].toString() == deletedId);
                notifyListeners();
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime subscription error: $e');
    }
  }

  Future<void> removeClient(String id) async {
    try {
      await _localDb.deleteClientLocally(id);
      _clients.removeWhere((client) => client['id'].toString() == id);
      notifyListeners();

      if (_supabase != null) {
        if (int.tryParse(id) != null) {
          await _supabase.from('clients').delete().match({'id': int.parse(id)});
        } else {
          await _supabase.from('clients').delete().match({'id': id});
        }
      }
      debugPrint('Client removed: $id');
    } catch (e) {
      debugPrint('Failed to remove client from Supabase: $e');
    }
  }

  Future<void> nextClient() async {
    if (_clients.isNotEmpty) {
      final firstId = _clients.first['id']?.toString();
      if (firstId != null) {
        await removeClient(firstId);
      }
    }
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    super.dispose();
  }
}
