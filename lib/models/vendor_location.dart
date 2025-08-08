import 'package:cloud_firestore/cloud_firestore.dart';

class VendorLocation {
  final String uid;
  final GeoPoint location;

  VendorLocation({ required this.uid, required this.location });
}
