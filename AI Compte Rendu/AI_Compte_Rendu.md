# Workshop 5 Report: Building an Offline-First Queue App with Geolocation


> **Simulation on Android Studio: Success**

---

## Part 1: AI Collaboration Log & Problem-Solving Journey

This section tracks the step-by-step collaboration between the student and the AI assistant inside Google Antigravity. It documents the natural, interactive prompts given during development, the real-world bugs encountered, and the technical solutions applied to complete Workshop 5.

### Environment Details
- **AI Model:** Gemini 3.8 Flash (Medium)
- **Environment:** Google Antigravity Agentic IDE
- **Operating System:** Windows 10 (x64)
- **Frameworks & Libraries:** Flutter SDK 3.38.5, SQLite (`sqflite` & `sqflite_common_ffi`), `geolocator`, `uuid`, Mockito, Supabase Flutter SDK

---

### Step-by-Step Interactive Prompts & Fixes

#### Step 1: Setting up Offline & Geolocation Dependencies
- **Student:**  
  > *"we're doing tp 5 today. We need to make the app work completely offline using SQLite and capture each client's GPS location. What packages do we need to add to `pubspec.yaml` to get SQLite, UUID generation, and geolocation working?"*
- **Problem:** The app previously relied solely on an active internet connection directly connected to Supabase. It had no local database engine and no device location modules.
- **Solution:**  
  Added the required packages to `pubspec.yaml`:
  - `sqflite: ^2.3.0` & `sqflite_common_ffi: ^2.3.0+2` for local SQLite persistence.
  - `path_provider: ^2.1.1` & `path: ^1.8.3` for database path management.
  - `geolocator: ^11.0.0` for device GPS coordinates.
  - `uuid: ^4.0.0` to generate unique client IDs offline.
  - `build_runner: ^2.4.0` in dev dependencies for mock generation.  
  Ran `flutter pub get` cleanly.

---

#### Step 2: Writing the Local Queue Service Test First (TDD)
- **Student:**  
  > *"The professor wants us to follow Test-Driven Development (TDD). How do I write the test first in `test/local_queue_service_test.dart` using an in-memory SQLite database before writing the actual service?"*
- **Problem:** Unit tests must run fast and completely isolated without creating or locking physical database files on disk.
- **Solution:**  
  Created `test/local_queue_service_test.dart` using `sqflite_common_ffi`'s `databaseFactoryFfi` in `setUpAll()`. The test inserts a test client into an in-memory database and asserts that `getUnsyncedClients()` returns the unsynced record with `is_synced = 0`.

---

#### Step 3: Implementing `LocalQueueService` with SQLite
- **Student:**  
  > *"Now that we have the test, let's implement `LocalQueueService` in `lib/local_queue_service.dart`. We need the `local_clients` table with id, name, lat, lng, created_at, and is_synced."*
- **Problem:** The local database schema must match Supabase's columns while introducing an `is_synced` integer flag (0 for offline/pending, 1 for synced).
- **Solution:**  
  Implemented `LocalQueueService` managing the SQLite table:
  ```sql
  CREATE TABLE local_clients (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    lat REAL,
    lng REAL,
    created_at TEXT NOT NULL,
    is_synced INTEGER NOT NULL DEFAULT 0
  )
  ```
  Added core CRUD methods: `insertClientLocally()`, `getClients()`, `getUnsyncedClients()`, `markClientAsSynced()`, `deleteClientLocally()`, and `close()`. The initial unit test passed immediately.

---

#### Step 4: Device Location Permissions & `GeolocationService`
- **Student:**  
  > *"For geolocation, what permissions do I need to put in AndroidManifest.xml and iOS Info.plist? And how should we write `GeolocationService.dart` so it safely asks for permission and gets the GPS position?"*
- **Problem:** Calling location APIs without declared permissions causes native runtime crashes. Additionally, if the user turns off GPS or denies permission, the app shouldn't hang or crash.
- **Solution:**  
  - Added `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` to `android/app/src/main/AndroidManifest.xml`.
  - Added `NSLocationWhenInUseUsageDescription` to `ios/Runner/Info.plist`.
  - Built `GeolocationService` in `lib/geolocation_service.dart`: checks permissions, requests them if denied, checks if location services are enabled, and fetches the coordinates with `LocationAccuracy.low` and a 10-second timeout. If denied or unavailable, it safely returns `null`.

---

#### Step 5: Updating `QueueProvider` for Offline Queueing
- **Student:**  
  > *"Let's update `QueueProvider.dart`. When someone adds a client, it should grab their location, generate a UUID for their ID, save them into SQLite right away, update the screen instantly, and then sync to Supabase in the background without freezing the UI."*
- **Problem:** Network calls to Supabase should never block the user interface. Offline clients need client-generated IDs since database auto-increment is unavailable without connectivity.
- **Solution:**  
  - In `addClient()`, generated `const Uuid().v4()`, fetched GPS position from `geoService`, stored the client in SQLite with `is_synced: 0`, and added them to `_clients` immediately for zero UI lag.
  - Used `unawaited(_syncLocalToRemote())` from `dart:async` so the sync runs asynchronously in the background.

---

#### Step 6: Fixing the `Unsupported operation: read-only` List Crash
- **Student:**  
  > *"I ran into an error when adding a client: `Unsupported operation: read-only` on `QueryResultSet.length=`. Also, when multiple syncs trigger at once, it tries to upload duplicate records. Why is that happening and how do we fix it?"*
- **Problem:**  
  1. SQLite's `db.query()` returns an unmodifiable `QueryResultSet`. Calling `_clients.add()` failed because the list was read-only.
  2. Simultaneous sync calls caused a race condition, sending the same unsynced records twice before they were marked as synced.
- **Solution:**  
  - Wrapped SQLite results in a modifiable list: `_clients = List<Map<String, dynamic>>.from(await _localDb.getClients());`.
  - Added a boolean lock `bool _isSyncing = false;` in `_syncLocalToRemote()` to guarantee only one sync operation runs at a time.

#### Step 7: Fixing Empty Client List on Startup
- **Student:**  
  > *"When I launch the app, the list is completely empty even though my Supabase database already has clients (like `iheb najjar`). Why aren't they showing up, and how do we fix `_loadQueue()` to fetch them?"*
- **Problem:** The original starter code for `_loadQueue()` only read from `_localDb.getClients()`. Since SQLite on a fresh device starts empty, existing remote records in Supabase were never fetched or cached.
- **Solution:**  
  - Added `_fetchRemoteClients()` inside `_loadQueue()`.
  - On launch, the app reads the local cache first for instant display, then fetches all existing clients from Supabase, caches them in SQLite with `is_synced = 1`, and refreshes the screen. Now existing clients appear immediately on startup.

---

#### Step 8: Cross-Platform Compatibility (Desktop & Web)
- **Student:**  
  > *"When I test on Edge browser, I get a popup asking 'Get Location' and the list had database errors. Is that browser popup normal? And how do we ensure SQLite doesn't crash on Desktop and Web?"*
- **Problem:**  
  - `sqflite` is built for mobile (Android/iOS) and throws platform channel exceptions on Flutter Web.
  - On Windows desktop, `sqflite` requires explicit `sqfliteFfiInit()` and `databaseFactoryFfi`.
  - The browser popup is standard HTML5 Geolocation behavior.
- **Solution:**  
  - Initialized `sqfliteFfiInit()` and `databaseFactory = databaseFactoryFfi;` in `lib/main.dart` for desktop.
  - Added an in-memory fallback store in `lib/local_queue_service.dart` when running on Web (`kIsWeb`), allowing seamless browser preview without native plugin crashes.
  - Clarified that the "Get Location" prompt is expected: clicking "Allow" tags the real GPS coordinates, while "Block" gracefully falls back to displaying `"Location not captured"`.

---

## Part 2: Architecture & Component Overview

The application follows an **Offline-First Clean Architecture**. Local SQLite acts as the primary source of truth, while Supabase provides real-time multi-device cloud synchronization.

```
                      ┌────────────────────────────────┐
                      │    WaitingRoomApp (UI Layer)   │
                      │  Live Queue & Location Badges  │
                      └───────────────┬────────────────┘
                                      │ Consumer / Provider
                                      ▼
                      ┌────────────────────────────────┐
                      │         QueueProvider          │
                      │ Offline State & Sync Manager   │
                      └───────┬───────────────┬────────┘
                              │               │
            ┌─────────────────┴─┐           ┌─┴─────────────────┐
            │                   │           │                   │
            ▼                   ▼           ▼                   ▼
┌───────────────────────┐ ┌───────────┐ ┌───────────────┐ ┌─────────────┐
│  LocalQueueService    │ │Geolocation│ │Supabase Client│ │ UUID v4 Gen │
│ (SQLite local_clients │ │  Service  │ │ (Remote Sync  │ │  (Offline   │
│  + is_synced flag)    │ │(GPS / Pos)│ │ + Realtime WS)│ │ Client IDs) │
└───────────────────────┘ └───────────┘ └───────────────┘ └─────────────┘
```

---

### Core Files & Responsibilities

#### 1. `lib/local_queue_service.dart` (Embedded SQLite Persistence)
- **Purpose:** Manages the local on-device SQLite database (`waiting_room.db`).
- **Table Schema:**
  - `id` (TEXT, PRIMARY KEY): Unique UUID string.
  - `name` (TEXT NOT NULL): Client name.
  - `lat`, `lng` (REAL): GPS coordinates.
  - `created_at` (TEXT NOT NULL): ISO 8601 timestamp.
  - `is_synced` (INTEGER NOT NULL DEFAULT 0): Sync status flag.
- **Key Methods:**
  - `insertClientLocally()`: Saves a record locally with conflict replacement.
  - `getClients()`: Returns all cached clients ordered by creation time.
  - `getUnsyncedClients()`: Retrieves pending records where `is_synced = 0`.
  - `markClientAsSynced()`: Updates `is_synced` to 1 once uploaded to Supabase.
  - `deleteClientLocally()`: Removes a record from the local database.

#### 2. `lib/geolocation_service.dart` (Hardware Location Wrapper)
- **Purpose:** Safely interfaces with device GPS hardware and browser location APIs.
- **Key Features:**
  - Verifies and requests location permissions at runtime.
  - Confirms hardware location services are enabled.
  - Uses `LocationAccuracy.low` for battery efficiency and rapid lock.
  - Enforces a 10-second safety timeout and returns `null` safely if permissions are denied.

#### 3. `lib/queue_provider.dart` (State Management & Sync Engine)
- **Purpose:** Central coordinator connecting UI, SQLite, Geolocation, and Supabase.
- **Key Workflows:**
  - **Cold Start (`_loadQueue`):** Loads local SQLite cache first for instant offline readiness, then queries Supabase (`_fetchRemoteClients`) to pull and cache any remote changes.
  - **Adding Clients (`addClient`):** Captures GPS position, assigns a UUID v4, saves to SQLite with `is_synced = 0`, updates the UI immediately, and triggers background upload via `unawaited(_syncLocalToRemote())`.
  - **Background Sync (`_syncLocalToRemote`):** Iterates through unsynced records, upserts them to Supabase, marks them synced, and handles schema variations gracefully.
  - **Real-Time Subscription:** Listens to PostgreSQL `INSERT` and `DELETE` events on the `clients` table, mirroring cloud updates directly to local SQLite and the UI.

#### 4. `lib/main.dart` (UI & Presentation Layer)
- **Platform Init:** Sets up desktop SQLite FFI and loads `.env` Supabase credentials.
- **Coordinate Display:** Truncates latitude and longitude to 4 decimal places (~11m precision) in the card subtitle:
  ```dart
  subtitle: Text(
    client['lat'] == null
      ? 'Location not captured'
      : '${client['lat']?.toStringAsFixed(4)}, ${client['lng']?.toStringAsFixed(4)}',
  ),
  ```
- **Testing Key:** Adds `Key('nextClientButton')` to the "Next Client" button for widget test interactions.

---

### Automated Test Suite (100% Passing)

All 7 unit and widget tests pass with zero warnings or failures:

| Test File | Type | Target Validated |
| :--- | :--- | :--- |
| `test/local_queue_service_test.dart` | Unit (In-Memory FFI) | SQLite table creation, record insertion, and unsynced query filtering. |
| `test/queue_provider_geolocation_test.dart` | Unit (Mockito) | Verifies `addClient()` tags mock GPS coordinates (`37.7749`, `-122.4194`). |
| `test/waiting_room_widget_test.dart` | Widget Test | Checks that `WaitingRoomScreen` renders client names and formatted coordinates. |
| `test/waiting_room_manager_test.dart` | Unit Test | Validates queue operations: adding, removing, and advancing (`nextClient`). |
| `test/queue_provider_test.dart` | Integration Unit | Verifies that local client saves trigger background remote sync. |

- **`flutter test` Output:** `00:03 +7: All tests passed!`
- **`flutter analyze` Output:** `No issues found!`
- **`flutter build apk --debug`:** `√ Built build\app\outputs\flutter-apk\app-debug.apk` (Exit code 0)
