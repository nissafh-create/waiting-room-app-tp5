import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:waiting_room_app/main.dart';
import 'package:waiting_room_app/queue_provider.dart';

import 'queue_provider_geolocation_test.mocks.dart';

void main() {
  testWidgets('Displays location when available', (tester) async {
    final provider = MockQueueProvider();
    when(provider.clients).thenReturn([
      {
        'id': '1',
        'name': 'Sam',
        'lat': 51.5074,
        'lng': -0.1278,
        'created_at': DateTime.now().toIso8601String(),
      }
    ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<QueueProvider>.value(
        value: provider,
        child: const MaterialApp(home: WaitingRoomScreen()),
      ),
    );

    expect(find.text('Sam'), findsOneWidget);
    expect(find.textContaining('51.5074'), findsOneWidget);
  });
}
