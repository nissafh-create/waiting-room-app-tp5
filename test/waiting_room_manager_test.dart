import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waiting_room_app/geolocation_service.dart';
import 'package:waiting_room_app/local_queue_service.dart';
import 'package:waiting_room_app/queue_provider.dart';

class FakeGeolocationService extends Fake implements GeolocationService {
  @override
  Future<Position?> getCurrentPosition() async => null;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await LocalQueueService(inMemory: true).close();
  });

  test('should add a client to the waiting list', () async {
    final manager = QueueProvider(
      geoService: FakeGeolocationService(),
      localDb: LocalQueueService(inMemory: true),
    );

    await manager.addClient('Ahmed haddad');

    expect(manager.clients.length, 1);
    expect(manager.clients.first['name'], 'Ahmed haddad');
  });

  test('should remove a client from the waiting list', () async {
    final manager = QueueProvider(
      geoService: FakeGeolocationService(),
      localDb: LocalQueueService(inMemory: true),
    );
    await manager.addClient('Client 1');
    await manager.addClient('Client 2');

    final clientId = manager.clients.first['id'].toString();
    await manager.removeClient(clientId);

    expect(manager.clients.length, 1);
    expect(manager.clients.first['name'], 'Client 2');
  });

  test('should remove the first client when nextClient() is called', () async {
    final manager = QueueProvider(
      geoService: FakeGeolocationService(),
      localDb: LocalQueueService(inMemory: true),
    );
    await manager.addClient('Client 1');
    await manager.addClient('Client 2');

    await manager.nextClient();

    expect(manager.clients.length, 1);
    expect(manager.clients.first['name'], 'Client 2');
  });
}
