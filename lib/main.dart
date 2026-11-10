import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waiting_room_app/queue_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI for desktop (Windows / Linux)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 1. Load the .env file
  await dotenv.load(fileName: ".env");

  // 2. Initialize Supabase using environment variables
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // 3. Sign in anonymously (optional - can be enabled in Supabase if needed)
  // try {
  //   final authResponse = await Supabase.instance.client.auth.signInAnonymously();
  //   debugPrint('Signed in anonymously as user: ${authResponse.user?.id}');
  // } catch (e) {
  //   debugPrint('Failed to sign in: $e');
  // }

  runApp(
    ChangeNotifierProvider(
      create: (context) => QueueProvider(),
      child: const WaitingRoomApp(),
    ),
  );
}

class WaitingRoomApp extends StatelessWidget {
  const WaitingRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ignore: no_leading_underscores_for_local_identifiers
    final TextEditingController _controller = TextEditingController();

    return MaterialApp(
      title: 'Waiting Room',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Waiting Room'),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Input Field
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(hintText: 'Enter name'),
                      onSubmitted: (name) {
                        if (name.trim().isNotEmpty) {
                          context.read<QueueProvider>().addClient(name);
                          _controller.clear();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (_controller.text.trim().isNotEmpty) {
                        context.read<QueueProvider>().addClient(_controller.text);
                        _controller.clear();
                      }
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Queue List
              Expanded(
                child: Consumer<QueueProvider>(
                  builder: (context, provider, _) {
                    if (provider.clients.isEmpty) {
                      return const Center(child: Text('No one in queue yet...'));
                    }
                    return ListView.builder(
                      itemCount: provider.clients.length,
                      itemBuilder: (context, index) {
                        final client = provider.clients[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(client['name'] ?? ''),
                            subtitle: Text(
                              client['lat'] == null
                                  ? 'Location not captured'
                                  : '${client['lat']?.toStringAsFixed(4)}, ${client['lng']?.toStringAsFixed(4)}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                context.read<QueueProvider>().removeClient(client['id'].toString());
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              // Next Button
              const SizedBox(height: 20),
              ElevatedButton.icon(
                key: const Key('nextClientButton'),
                onPressed: () {
                  context.read<QueueProvider>().nextClient();
                },
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Next Client'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef WaitingRoomScreen = WaitingRoomApp;