import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<User?> registerWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      return result.user;
    } catch (e) {
      // TODO: Implement proper logging instead of print
      // print(e.toString());
      return null;
    }
  }

  Future<void> createUserDocument(String uid, String name, String phoneNumber,
      String businessName, String aadharCardNumber, String email, String fssaiCode, String businessAddress, String gstin) async {
    await _db.collection('vendors').doc(uid).set({
      'name': name,
      'phoneNumber': phoneNumber,
      'businessName': businessName,
      'aadharCardNumber': aadharCardNumber,
      'email': email,
      'uniqueId': (100000 + Random().nextInt(900000)).toString(),
      'managerId': null,
      'fssaiCode': fssaiCode,
      'businessAddress': businessAddress,
      'gstin': gstin,
      'menu': [
        {
          'name': 'Cream Bun',
          'mrp': 25,
          'sellingPrice': 15,
          'description': 'Soft, cream-filled bun perfect for a sweet snack.',
          'stock': 0,
          'date': DateTime.now()
        },
        {
          'name': 'Power Eggs',
          'mrp': 75,
          'sellingPrice': 50,
          'description': '2 eggs tossed in spicy masala.',
          'stock': 0,
          'date': DateTime.now()
        },
        {
          'name': 'Chicken Bun',
          'mrp': 80,
          'sellingPrice': 60,
          'description': 'Fluffy bun stuffed with rich chicken curry.',
          'stock': 0,
          'date': DateTime.now()
        },
        {
          'name': 'Smart Biryani',
          'mrp': 175,
          'sellingPrice': 125,
          'description': '400g of fragrant kushka rice served with chicken curry.',
          'stock': 0,
          'date': DateTime.now()
        },
        {
          'name': 'Brownie',
          'mrp': 75,
          'sellingPrice': 50,
          'description': 'Decadent, fudgy chocolate brownie bite.',
          'stock': 0,
          'date': DateTime.now()
        },
        {
          'name': 'Rich Chocolate Cake',
          'mrp': 75,
          'sellingPrice': 50,
          'description': 'Moist chocolate sponge layered with ganache.',
          'stock': 0,
          'date': DateTime.now()
        },
        {
          'name': 'Chicken Pickle',
          'mrp': 500,
          'sellingPrice': 400,
          'description': '250g jar of homemade spicy chicken pickle.',
          'stock': 0,
          'date': DateTime.now()
        }
      ]
    });
  }

  Stream<User?> get user {
    return _auth.authStateChanges();
  }

  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      return result.user;
    } catch (e) {
      // TODO: Implement proper logging instead of print
      // print(e.toString());
      return null;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
