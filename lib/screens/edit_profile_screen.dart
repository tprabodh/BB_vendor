import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneNumberController;
  late TextEditingController _aadharCardNumberController;
  late TextEditingController _emailController;
  late TextEditingController _businessAddressController;
  late TextEditingController _uniqueIdController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneNumberController = TextEditingController();
    _aadharCardNumberController = TextEditingController();
    _emailController = TextEditingController();
    _businessAddressController = TextEditingController();
    _uniqueIdController = TextEditingController();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneNumberController.dispose();
    _aadharCardNumberController.dispose();
    _emailController.dispose();
    _businessAddressController.dispose();
    _uniqueIdController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('vendors').doc(user.uid).get();
      if (userDoc.exists) {
        setState(() {
          _nameController.text = userDoc['name'] ?? '';
          _phoneNumberController.text = userDoc['phoneNumber'] ?? '';
          _aadharCardNumberController.text = userDoc['aadharCardNumber'] ?? '';
          _emailController.text = userDoc['email'] ?? '';
          _businessAddressController.text = userDoc['businessAddress'] ?? '';
          _uniqueIdController.text = userDoc['uniqueId'] ?? '';
        });
      }
    }
  }

  Future<void> _updateProfile() async {
    if (_formKey.currentState!.validate()) {
      String newPhoneNumber = _phoneNumberController.text.trim();

      // Phone number length validation
      if (newPhoneNumber.length != 10) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact number must be 10 digits long.')),
        );
        return;
      }

      try {
        User? user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // Phone number uniqueness validation
          QuerySnapshot phoneQuery = await FirebaseFirestore.instance
              .collection('vendors')
              .where('phoneNumber', isEqualTo: newPhoneNumber)
              .get();

          if (phoneQuery.docs.isNotEmpty && phoneQuery.docs.first.id != user.uid) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('This contact number is already in use by another vendor.')),
            );
            return;
          }

          await FirebaseFirestore.instance.collection('vendors').doc(user.uid).update({
            'name': _nameController.text,
            'phoneNumber': newPhoneNumber,
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully!')),
          );
          Navigator.pop(context); // Go back to the previous screen
        }
      } on FirebaseException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: ${e.message}')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (val) => val!.isEmpty ? 'Please enter your name' : null,
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _phoneNumberController,
                decoration: const InputDecoration(labelText: 'Contact Number'),
                keyboardType: TextInputType.phone,
                validator: (val) =>
                    val!.isEmpty ? 'Please enter your contact number' : null,
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _aadharCardNumberController,
                decoration: const InputDecoration(labelText: 'Aadhar Card Number'),
                enabled: false,
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                enabled: false,
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _businessAddressController,
                decoration: const InputDecoration(labelText: 'Address'),
                enabled: false,
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _uniqueIdController,
                decoration: const InputDecoration(labelText: 'Unique ID'),
                enabled: false,
              ),
              const SizedBox(height: 24.0),
              ElevatedButton(
                onPressed: _updateProfile,
                child: const Text('Update Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
