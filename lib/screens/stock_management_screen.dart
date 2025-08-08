import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vendor_app/auth/auth_service.dart';
import 'package:vendor_app/services/location_service.dart';
import 'package:vendor_app/screens/login_screen.dart';
import 'package:vendor_app/screens/edit_profile_screen.dart';

class StockManagementScreen extends StatefulWidget {
  const StockManagementScreen({super.key});
  @override
  State<StockManagementScreen> createState() => _StockManagementScreenState();
}

class _StockManagementScreenState extends State<StockManagementScreen> {
  final AuthService _auth = AuthService();
  final LocationService _locationService = LocationService();
  final _formKey = GlobalKey<FormState>();

  bool _isTracking = false; // Initial value, will be updated by Firestore
  bool _isEditing = false;
  List<Map<String, dynamic>> _menuItems = [];
  List<Map<String, dynamic>> _editingMenuItems = [];
  List<TextEditingController> _stockControllers = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    for (var controller in _stockControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Management'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: <Widget>[
          IconButton(
            icon: Icon(_isEditing ? Icons.cancel : Icons.edit),
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
                if (_isEditing) {
                  _editingMenuItems =
                      _menuItems.map((item) => Map<String, dynamic>.from(item)).toList();
                  // Initialize controllers for editing
                  _stockControllers.clear();
                  for (var item in _editingMenuItems) {
                    _stockControllers.add(TextEditingController(text: '')); // Clear for adding
                  }
                } else {
                  // Clear controllers when exiting editing mode
                  for (var controller in _stockControllers) {
                    controller.clear();
                  }
                }
              });
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('vendors').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var userData = snapshot.data!.data() as Map<String, dynamic>;

          List<dynamic> menuData = userData['menu'] ?? [];
          List<Map<String, dynamic>> newMenuItems = [];
          bool stockResetOccurred = false;

          DateTime now = DateTime.now();
          DateTime today = DateTime(now.year, now.month, now.day);

          // Re-initialize controllers if menuData changes or on first load
          if (_stockControllers.length != menuData.length) {
            for (var controller in _stockControllers) {
              controller.dispose();
            }
            _stockControllers = List.generate(menuData.length, (index) => TextEditingController());
          }

          for (int i = 0; i < menuData.length; i++) {
            Map<String, dynamic> menuItem = Map.from(menuData[i]);

            menuItem['totalStockUpdates'] = (menuItem['totalStockUpdates'] as num?)?.toInt() ?? 0;
            menuItem['todayStockAdded'] = (menuItem['todayStockAdded'] as num?)?.toInt() ?? 0;
            menuItem['todayStockSold'] = (menuItem['todayStockSold'] as num?)?.toInt() ?? 0;
            menuItem['stock'] = (menuItem['stock'] as num?)?.toInt() ?? 0;

            // If the item's date is not today, reset stock for display purposes
            if (menuItem['date'] is Timestamp) {
              DateTime itemDate = (menuItem['date'] as Timestamp).toDate();
              DateTime itemDay = DateTime(itemDate.year, itemDate.month, itemDate.day);
              if (itemDay.year != today.year || itemDay.month != today.month || itemDay.day != today.day) {
                menuItem['stock'] = 0; // Set stock to 0 for display if not today's date
              }
            }
            menuItem['date'] = menuItem['date'] ?? Timestamp.fromDate(today); // Use 'date' for daily reset

            // Daily reset logic using 'date' field
            if (menuItem['date'] is Timestamp) {
              DateTime lastUpdateDate = (menuItem['date'] as Timestamp).toDate();
              DateTime lastUpdateDay = DateTime(lastUpdateDate.year, lastUpdateDate.month, lastUpdateDate.day);

              if (lastUpdateDay.year != today.year || lastUpdateDay.month != today.month || lastUpdateDay.day != today.day) {
                menuItem['todayStockAdded'] = 0;
                menuItem['todayStockSold'] = 0;
                menuItem['totalStockUpdates'] = 0; // Reset totalStockUpdates on new day
                stockResetOccurred = true;
              }
            } else {
              // If 'date' is not a Timestamp, initialize it and reset today's counts
              menuItem['todayStockAdded'] = 0;
              menuItem['todayStockSold'] = 0;
              menuItem['totalStockUpdates'] = 0; // Explicitly reset here
              stockResetOccurred = true;
            }

            newMenuItems.add(menuItem);
            // Update controller text when not editing
            if (!_isEditing) {
              _stockControllers[i].text = menuItem['stock'].toString();
            }
          }
          _menuItems = newMenuItems;

          if (stockResetOccurred) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              WriteBatch batch = FirebaseFirestore.instance.batch();
              batch.update(FirebaseFirestore.instance.collection('vendors').doc(user.uid), {
                'menu': _menuItems.map((item) {
                  return {
                    ...item,
                    // Ensure 'date' is always a Timestamp when saving to Firestore
                    'date': item['date'] is DateTime ? Timestamp.fromDate(item['date'] as DateTime) : item['date'],
                  };
                }).toList(),
              });
              await batch.commit();
            });
          }

          _isTracking = userData['isTracking'] ?? false; // Update _isTracking state from Firestore

          return SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 50.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      title: const Text('Live Location Tracking'),
                      value: _isTracking, // Use the state variable
                      onChanged: (bool value) async {
                        setState(() {
                          _isTracking = value; // Update the local state immediately for responsiveness
                        });
                        if (user != null) {
                          await FirebaseFirestore.instance.collection('vendors').doc(user.uid).update({
                            'isTracking': value,
                            'working': value, // Assuming 'working' state is tied to tracking
                          });
                        }
                        if (value) {
                          _locationService.startTracking(user!.uid);
                        } else {
                          _locationService.stopTracking();
                        }
                      },
                      secondary: const Icon(Icons.location_on),
                    ),
                    const SizedBox(height: 20.0),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                        );
                      },
                      child: const Text('Edit Profile'),
                    ),
                    const SizedBox(height: 20.0),
                    const Text(
                      'Stock Management',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10.0),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _isEditing ? _editingMenuItems.length : _menuItems.length,
                      itemBuilder: (context, index) {
                        final Map<String, dynamic> item = _isEditing ? _editingMenuItems[index] : _menuItems[index];
                        final int originalStock = (_menuItems.isNotEmpty && index < _menuItems.length
                            ? (_menuItems[index]['stock'] as num?)?.toInt() ?? 0
                            : 0);


                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 10.0),
                          child: Padding(
                            padding: const EdgeInsets.all(15.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${item['name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0)),
                                const SizedBox(height: 5.0),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _isEditing
                                        ? Text('Current: ${item['stock'] ?? 0} + Add:', style: TextStyle(fontSize: 16.0))
                                        : const Text('Stock:', style: TextStyle(fontSize: 16.0)),
                                    const SizedBox(width: 10.0),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _stockControllers.length > index ? _stockControllers[index] : null,
                                        keyboardType: TextInputType.number,
                                        enabled: _isEditing,
                                        textAlign: TextAlign.center,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
                                          hintText: _isEditing ? 'Qty' : null, // Hint text for adding quantity
                                        ),
                                        onChanged: (val) {
                                          // The TextEditingController will hold the value. No direct stock update here.
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5.0),
                                Text('Today Added: ${item['todayStockAdded'] ?? 0}'),
                                Text('Today Sold: ${item['todayStockSold'] ?? 0}'),
                                Text('Remaining: ${item['stock'] ?? 0}'), // Display current total stock
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20.0),
                    const Text(
                      'Daily Updates Summary',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10.0),
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Padding(
                        padding: const EdgeInsets.all(15.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Stock Updates: ${(_menuItems.fold<int>(0, (currentMax, item) {
                              int itemTotalUpdates = (item['totalStockUpdates'] as num?)?.toInt() ?? 0;
                              return itemTotalUpdates > currentMax ? itemTotalUpdates : currentMax;
                            }))}'),
                            Text('Total Added Today: ${(_menuItems.fold<int>(0, (currentSum, item) => currentSum + ((item['todayStockAdded'] as num?)?.toInt() ?? 0)))}'),
                            Text('Total Sold Today: ${(_menuItems.fold<int>(0, (currentSum, item) => currentSum + ((item['todayStockSold'] as num?)?.toInt() ?? 0)))}'),
                                                                                    Text('Total Remaining: ${(_menuItems.fold<int>(0, (currentSum, item) => currentSum + ((item['stock'] as num?)?.toInt() ?? 0)))}'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isEditing)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 50),
                ),
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null) {
                      WriteBatch batch = FirebaseFirestore.instance.batch();

                      // Update totalStockUpdates for edited items based on how stock changed
                      for (int i = 0; i < _editingMenuItems.length; i++) {
                        final editedItem = _editingMenuItems[i];
                        final originalItem = _menuItems[i]; // Assuming _menuItems is up-to-date with fetched data

                        final int originalStockValue = (originalItem['stock'] as num?)?.toInt() ?? 0;
                        final int editedStockValue = (editedItem['stock'] as num?)?.toInt() ?? 0;

                        // Read quantity to add from controller
                        int quantityToAdd = int.tryParse(_stockControllers[i].text) ?? 0;

                        if (quantityToAdd > 0) {
                          // Update the stock by adding the quantity
                          editedItem['stock'] = originalStockValue + quantityToAdd;

                          // Update todayStockAdded
                          editedItem['todayStockAdded'] = (editedItem['todayStockAdded'] ?? 0) + quantityToAdd;

                          // Update the date
                          editedItem['date'] = Timestamp.fromDate(DateTime.now());

                          // Increment totalStockUpdates if stock changed
                          editedItem['totalStockUpdates'] = (editedItem['totalStockUpdates'] ?? 0) + 1;
                        }
                      }


                      DocumentReference vendorRef = FirebaseFirestore.instance.collection('vendors').doc(user.uid);
                      batch.update(vendorRef, {
                        'menu': _editingMenuItems.map((item) {
                          return {
                            ...item,
                            'date': item['date'] is DateTime ? Timestamp.fromDate(item['date'] as DateTime) : item['date'],
                            'totalStockAdded': item['todayStockAdded'] ?? 0,
                            'todayStockSold': item['todayStockSold'] ?? 0,
                            'totalStockUpdates': item['totalStockUpdates'] ?? 0,
                          };
                        }).toList(),
                      });

                      String todayDateString = DateTime.now().toIso8601String().split('T')[0];
                      DocumentReference stockHistoryRef = FirebaseFirestore.instance.collection('vendor_stock_history').doc(user.uid);
                      batch.set(stockHistoryRef, {
                        todayDateString: _editingMenuItems.map((item) {
                          return {
                            ...item,
                            'date': item['date'] is DateTime ? Timestamp.fromDate(item['date'] as DateTime) : item['date'],
                          };
                        }).toList(),
                      }, SetOptions(merge: true));

                      await batch.commit();

                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile updated successfully!')),
                      );
                      setState(() {
                        _isEditing = false;
                      });
                    }
                  }
                },
                child: const Text('Update'),
              ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () async {
                final bool? confirm = await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text('Confirm Logout'),
                      content: const Text('Are you sure you want to log out?'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Logout'),
                        ),
                      ],
                    );
                  },
                );
                if (confirm == true) {
                  await _auth.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (Route<dynamic> route) => false,
                  );
                }
              },
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}