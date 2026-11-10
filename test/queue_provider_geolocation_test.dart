import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waiting_room_app/geolocation_service.dart';
import 'package:waiting_room_app/local_queue_service.dart';
import 'package:waiting_room_app/queue_provider.dart';

import 'queue_provider_geolocation_test.mocks.dart';

@GenerateMocks([GeolocationService, QueueProvider])
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await LocalQueueService(inMemory: true).database;
    await db.delete(LocalQueueService.tableName);
  });

  test('addClient saves client with geolocation', () async {
    final mockGeo = MockGeolocationService();
    final mockPos = Position(
      latitude: 37.7749,
      longitude: -122.4194,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );

    when(mockGeo.getCurrentPosition()).thenAnswer((_) async => mockPos);

    final provider = QueueProvider(
      geoService: mockGeo,
      localDb: LocalQueueService(inMemory: true),
    );

    await provider.addClient('Test User');

    final client = provider.clients.last;
    expect(client['lat'], 37.7749);
    expect(client['lng'], -122.4194);
  });
}
