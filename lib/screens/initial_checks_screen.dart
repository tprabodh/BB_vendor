import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:location/location.dart';
import 'package:vendor_app/screens/wrapper.dart';

class InitialChecksScreen extends StatefulWidget {
  @override
  _InitialChecksScreenState createState() => _InitialChecksScreenState();
}

class _InitialChecksScreenState extends State<InitialChecksScreen> {
  bool _isLoading = true;
  bool _hasInternet = false;
  bool _hasLocationPermission = false;
  final Location _location = Location();

  @override
  void initState() {
    super.initState();
    _performChecks();
  }

  Future<void> _performChecks() async {
    setState(() {
      _isLoading = true;
    });

    // Check for internet connectivity
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      setState(() {
        _hasInternet = false;
        _isLoading = false;
      });
      return;
    }
    _hasInternet = true;

    // Check for location permission
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        setState(() {
          _hasLocationPermission = false;
          _isLoading = false;
        });
        return;
      }
    }

    PermissionStatus permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied || permission == PermissionStatus.deniedForever) {
      permission = await _location.requestPermission();
      if (permission != PermissionStatus.granted) {
        setState(() {
          _hasLocationPermission = false;
          _isLoading = false;
        });
        return;
      }
    }

    _hasLocationPermission = true;

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasInternet) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Internet is required for this app.'),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _performChecks,
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasLocationPermission) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Location permission is required for this app.'),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _performChecks,
                child: Text('Grant Permission'),
              ),
            ],
          ),
        ),
      );
    }

    return Wrapper();
  }
}
