import 'package:flutter/material.dart';
import 'package:vendor_app/auth/auth_service.dart';
import 'package:vendor_app/screens/registration_screen.dart';
import 'package:vendor_app/screens/wrapper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService();
  final _formKey = GlobalKey<FormState>();

  String email = '';
  String password = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 50.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 20.0),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (val) => val!.isEmpty ? 'Enter an email' : null,
                      onChanged: (val) {
                        setState(() => email = val);
                      },
                    ),
                    const SizedBox(height: 20.0),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      validator: (val) =>
                          val!.length < 6 ? 'Enter a password 6+ chars long' : null,
                      onChanged: (val) {
                        setState(() => password = val);
                      },
                    ),
                    const SizedBox(height: 20.0),
                    ElevatedButton(
                      child: const Text('Sign In'),
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          setState(() {
                            _isLoading = true;
                          });
                          dynamic result =
                              await _auth.signInWithEmailAndPassword(email, password);
                          if (mounted) {
                            setState(() {
                              _isLoading = false;
                            });
                          }
                          if (result == null) {
                            if (!context.mounted) return;
                            // TODO: Implement proper logging instead of print
                            // print('error signing in');
                          } else {
                            // TODO: Implement proper logging instead of print
                            // print('signed in');
                            // print(result.uid);
                            if (!context.mounted) return;
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (context) => const Wrapper()),
                              (Route<dynamic> route) => false,
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 12.0),
                    ElevatedButton(
                      child: const Text('Register'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegistrationScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 12.0),
                    TextButton(
                      child: const Text('Forgot Password?'),
                      onPressed: () {
                        _showForgotPasswordDialog();
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String resetEmail = '';
        return AlertDialog(
          title: const Text('Forgot Password'),
          content: TextFormField(
            decoration: const InputDecoration(labelText: 'Email'),
            onChanged: (val) {
              resetEmail = val;
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            TextButton(
              child: const Text('Send'),
              onPressed: () async {
                await _auth.sendPasswordResetEmail(resetEmail);
                if (!context.mounted) return;
                Navigator.pop(context);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password reset email sent'),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
