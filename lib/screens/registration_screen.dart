import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:vendor_app/auth/auth_service.dart';
import 'package:vendor_app/screens/initial_checks_screen.dart';

import 'home_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final AuthService _auth = AuthService();
  final _formKey = GlobalKey<FormState>();

  String name = '';
  String phoneNumber = '';
  String businessName = 'Yasaswy Universal';
  String aadharCardNumber = '';
  String email = '';
  String password = '';
  String fssaiCode = '123412341234';
  String businessAddress = '';
  String gstin = '123412341234';
  bool _isLoading = false;

  Future<bool> _isAadharUnique(String aadharNumber) async {
    final result = await FirebaseFirestore.instance
        .collection('vendors')
        .where('aadharCardNumber', isEqualTo: aadharNumber)
        .get();
    return result.docs.isEmpty;
  }

  Future<bool> _isContactNumberUnique(String contactNumber) async {
    final result = await FirebaseFirestore.instance
        .collection('vendors')
        .where('phoneNumber', isEqualTo: contactNumber)
        .get();
    return result.docs.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 20.0, horizontal: 50.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 20.0),
                      TextFormField(
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: (val) =>
                            val!.isEmpty ? 'Enter your name' : null,
                        onChanged: (val) {
                          setState(() => name = val);
                        },
                      ),
                      const SizedBox(height: 20.0),
                      TextFormField(
                        decoration:
                            const InputDecoration(labelText: 'Contact Number'),
                        keyboardType: TextInputType.phone,
                        validator: (val) {
                          if (val!.isEmpty) {
                            return 'Enter your Contact number';
                          }
                          if (val.length != 10) {
                            return 'Contact number must be 10 digits';
                          }
                          return null;
                        },
                        onChanged: (val) {
                          setState(() => phoneNumber = val);
                        },
                      ),
                      const SizedBox(height: 20.0),
                      TextFormField(
                        decoration: const InputDecoration(
                            labelText: 'Aadhar Card Number'),
                        keyboardType: TextInputType.number,
                        validator: (val) {
                          if (val!.isEmpty) {
                            return 'Enter your Aadhar card number';
                          }
                          if (val.length != 12) {
                            return 'Aadhar number must be 12 digits';
                          }
                          return null;
                        },
                        onChanged: (val) {
                          setState(() => aadharCardNumber = val);
                        },
                      ),
                      const SizedBox(height: 20.0),
                      TextFormField(
                        decoration: const InputDecoration(labelText: 'Address'),
                        validator: (val) =>
                            val!.isEmpty ? 'Enter your Address' : null,
                        onChanged: (val) {
                          setState(() => businessAddress = val);
                        },
                      ),
                      const SizedBox(height: 20.0),
                      TextFormField(
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                        validator: (val) =>
                            val!.isEmpty ? 'Enter an email' : null,
                        onChanged: (val) {
                          setState(() => email = val);
                        },
                      ),
                      const SizedBox(height: 20.0),
                      TextFormField(
                        decoration: const InputDecoration(labelText: 'Password'),
                        obscureText: true,
                        validator: (val) => val!.length < 6
                            ? 'Enter a password 6+ chars long'
                            : null,
                        onChanged: (val) {
                          setState(() => password = val);
                        },
                      ),
                      const SizedBox(height: 20.0),
                      ElevatedButton(
                        child: const Text('Register'),
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            setState(() {
                              _isLoading = true;
                            });

                            bool isAadharUnique =
                                await _isAadharUnique(aadharCardNumber);

                            if (!mounted) return;

                            if (!isAadharUnique) {
                              setState(() {
                                _isLoading = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('This Aadhar number already exists.'),
                                ),
                              );
                              return;
                            }

                            bool isContactNumberUnique = await _isContactNumberUnique(phoneNumber);

                            if (!mounted) return;

                            if (!isContactNumberUnique) {
                              setState(() {
                                _isLoading = false;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('This contact number already exists.'),
                                ),
                              );
                              return;
                            }

                            dynamic result = await _auth
                                .registerWithEmailAndPassword(email, password);
                            
                            if (!mounted) return;

                            if (result == null) {
                              setState(() {
                                _isLoading = false;
                              });
                              // TODO: Implement proper logging instead of print
                              // print('error registering');
                            } else {
                              await _auth.createUserDocument(
                                result.uid,
                                name,
                                phoneNumber,
                                businessName,
                                aadharCardNumber,
                                email,
                                fssaiCode,
                                businessAddress,
                                gstin,
                              );
                              
                              if (!mounted) return;
                              
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (context) => InitialChecksScreen()),
                                (Route<dynamic> route) => false,
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
