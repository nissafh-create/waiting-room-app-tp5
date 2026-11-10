// lib/geolocation_service.dart
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GeolocationService {
  Future<Position?> getCurrentPosition() async {
    // 1. Check & request permission
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return null;
    }

    // 2. Ensure location services are enabled
    if (!(await Geolocator.isLocationServiceEnabled())) {
      return null;
    }

    // 3. Fetch position
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('Geolocation error: $e');
      return null;
    }
  }
}
