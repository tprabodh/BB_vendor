import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';

class LocationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Location _location = Location();
  Timer? _timer;

  void startTracking(String uid) {
    _timer = Timer.periodic(Duration(seconds: 30), (timer) async {
      LocationData locationData = await _location.getLocation();
      _db.collection('vendors').doc(uid).update({
        'location': GeoPoint(locationData.latitude!, locationData.longitude!)
      });
    });
  }

  void stopTracking() {
    _timer?.cancel();
  }
}
