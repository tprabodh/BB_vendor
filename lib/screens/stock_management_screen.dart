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
          
          DateTime now = DateTime.now();
          DateTime today = DateTime(now.year, now.month, now.day);

          DateTime lastUpdateDate = today;
          if (menuData.isNotEmpty && menuData.first['date'] is Timestamp) {
            lastUpdateDate = (menuData.first['date'] as Timestamp).toDate();
          }
          DateTime lastUpdateDay = DateTime(lastUpdateDate.year, lastUpdateDate.month, lastUpdateDate.day);

          if(lastUpdateDay.isBefore(today)) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              WriteBatch batch = FirebaseFirestore.instance.batch();
              DocumentReference vendorRef = FirebaseFirestore.instance.collection('vendors').doc(user.uid);
              DocumentReference stockHistoryRef = FirebaseFirestore.instance.collection('vendor_stock_history').doc(user.uid);

              // 1. Save last active day's data
              String lastActiveDateString = lastUpdateDay.toIso8601String().split('T')[0];
              batch.set(stockHistoryRef, {
                lastActiveDateString: menuData.map((item) => {
                  'name': item['name'],
                  'stock': item['stock'],
                  'todayStockAdded': item['todayStockAdded'],
                  'todayStockSold': item['todayStockSold'],
                }).toList(),
              }, SetOptions(merge: true));

              // 2. Fill in gaps for inactive days
              int daysDifference = today.difference(lastUpdateDay).inDays;
              for (int i = 1; i < daysDifference; i++) {
                DateTime inactiveDay = lastUpdateDay.add(Duration(days: i));
                String inactiveDateString = inactiveDay.toIso8601String().split('T')[0];
                batch.set(stockHistoryRef, {
                  inactiveDateString: menuData.map((item) => {
                    'name': item['name'],
                    'stock': 0,
                    'todayStockAdded': 0,
                    'todayStockSold': 0,
                    'stockShiftedToday': 0,
                  }).toList(),
                }, SetOptions(merge: true));
              }

              // 3. Prune data older than 60 days
              DocumentSnapshot stockHistorySnapshot = await stockHistoryRef.get();
              if (stockHistorySnapshot.exists) {
                Map<String, dynamic> stockHistoryData = stockHistorySnapshot.data() as Map<String, dynamic>;
                Map<String, dynamic> updatedStockHistoryData = {};
                DateTime sixtyDaysAgo = today.subtract(const Duration(days: 60));

                stockHistoryData.forEach((key, value) {
                  try {
                    DateTime recordDate = DateTime.parse(key);
                    if (recordDate.isAfter(sixtyDaysAgo) || recordDate.isAtSameMomentAs(sixtyDaysAgo)) {
                      updatedStockHistoryData[key] = value;
                    }
                  } catch (e) {
                    // Ignore keys that are not valid dates
                  }
                });
                batch.set(stockHistoryRef, updatedStockHistoryData);
              }

              // 4. Reset today's stock data in the main vendor document
              List<Map<String, dynamic>> resetMenuItems = menuData.map((item) {
                final Map<String, dynamic> modifiableItem = Map<String, dynamic>.from(item as Map);
                modifiableItem['stock'] = 0;
                modifiableItem['todayStockAdded'] = 0;
                modifiableItem['todayStockSold'] = 0;
                modifiableItem['totalStockUpdates'] = 0;
                modifiableItem['date'] = Timestamp.fromDate(today);
                return modifiableItem;
              }).toList();

              batch.update(vendorRef, {'menu': resetMenuItems});

              await batch.commit();
            });
          }

          _menuItems = menuData.map((item) => Map<String, dynamic>.from(item as Map)).toList();

          // Re-initialize controllers if menuData changes or on first load
          if (_stockControllers.length != _menuItems.length) {
            for (var controller in _stockControllers) {
              controller.dispose();
            }
            _stockControllers = List.generate(_menuItems.length, (index) => TextEditingController(text: (_menuItems[index]['stock'] ?? 0).toString()));
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                            );
                          },
                          child: const Text('Edit Profile'),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: () {
                            _showShiftStockDialog();
                          },
                          child: const Text('Shift Stock'),
                        ),
                      ],
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
                      
                      // Prune data older than 60 days
                      DocumentSnapshot stockHistorySnapshot = await stockHistoryRef.get();
                      if (stockHistorySnapshot.exists) {
                        Map<String, dynamic> stockHistoryData = stockHistorySnapshot.data() as Map<String, dynamic>;
                        Map<String, dynamic> updatedStockHistoryData = {};
                        DateTime today = DateTime.now();
                        DateTime sixtyDaysAgo = today.subtract(const Duration(days: 60));

                        stockHistoryData.forEach((key, value) {
                          try {
                            DateTime recordDate = DateTime.parse(key);
                            if (recordDate.isAfter(sixtyDaysAgo) || recordDate.isAtSameMomentAs(sixtyDaysAgo)) {
                              updatedStockHistoryData[key] = value;
                            }
                          } catch (e) {
                            // Ignore keys that are not valid dates
                          }
                        });
                        batch.set(stockHistoryRef, updatedStockHistoryData);
                      }

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

  void _showShiftStockDialog() {
    final _shiftFormKey = GlobalKey<FormState>();
    List<TextEditingController> _shiftControllers = List.generate(_menuItems.length, (index) => TextEditingController());
    TextEditingController _vendorIdController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Shift Stock'),
              content: Form(
                key: _shiftFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 300, // Give a fixed height to the ListView
                        width: double.maxFinite,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _menuItems.length,
                          itemBuilder: (context, index) {
                            final item = _menuItems[index];
                            return Row(
                              children: [
                                Expanded(child: Text('${item['name']} (${item['stock']})')),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: _shiftControllers[index],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(hintText: 'Qty'),
                                    validator: (val) {
                                      if (val != null && val.isNotEmpty) {
                                        int? qty = int.tryParse(val);
                                        if (qty == null || qty < 0) {
                                          return 'Invalid';
                                        }
                                        if (qty > (item['stock'] as int)) {
                                          return 'Too high';
                                        }
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _vendorIdController,
                        decoration: const InputDecoration(labelText: 'Destination Vendor ID'),
                        validator: (val) {
                          if (val == null || val.isEmpty || val.length != 6) {
                            return 'Enter a 6-digit ID';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_shiftFormKey.currentState!.validate()) {
                      final sourceUser = FirebaseAuth.instance.currentUser;
                      if (sourceUser == null) return;

                      final destinationVendorId = _vendorIdController.text;
                      final querySnapshot = await FirebaseFirestore.instance
                          .collection('vendors')
                          .where('uniqueId', isEqualTo: destinationVendorId)
                          .limit(1)
                          .get();

                      if (querySnapshot.docs.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Destination vendor not found')),
                        );
                        return;
                      }
                      final destinationVendorDoc = querySnapshot.docs.first;

                      WriteBatch batch = FirebaseFirestore.instance.batch();

                      // Update source vendor
                      DocumentReference sourceVendorRef = FirebaseFirestore.instance.collection('vendors').doc(sourceUser.uid);
                      List<Map<String, dynamic>> updatedSourceMenu = [];
                      for (int i = 0; i < _menuItems.length; i++) {
                        final item = Map<String, dynamic>.from(_menuItems[i]);
                        int shiftQty = int.tryParse(_shiftControllers[i].text) ?? 0;
                        if (shiftQty > 0) {
                          item['stock'] = (item['stock'] as int) - shiftQty;
                          item['stockShiftedToday'] = (item['stockShiftedToday'] ?? 0) + shiftQty;
                        }
                        updatedSourceMenu.add(item);
                      }
                      batch.update(sourceVendorRef, {'menu': updatedSourceMenu});

                      // Update destination vendor
                      DocumentReference destinationVendorRef = destinationVendorDoc.reference;
                      List<dynamic> destinationMenuData = destinationVendorDoc.data()['menu'] ?? [];
                      List<Map<String, dynamic>> updatedDestinationMenu = [];
                      for (var destItemData in destinationMenuData) {
                        final destItem = Map<String, dynamic>.from(destItemData as Map);
                        int sourceItemIndex = _menuItems.indexWhere((srcItem) => srcItem['name'] == destItem['name']);
                        if(sourceItemIndex != -1) {
                            int shiftQty = int.tryParse(_shiftControllers[sourceItemIndex].text) ?? 0;
                            if(shiftQty > 0) {
                                destItem['stock'] = (destItem['stock'] as int) + shiftQty;
                                destItem['todayStockAdded'] = (destItem['todayStockAdded'] ?? 0) + shiftQty;
                                destItem['totalStockUpdates'] = (destItem['totalStockUpdates'] ?? 0) + 1;
                                destItem['date'] = Timestamp.now();
                            }
                        }
                        updatedDestinationMenu.add(destItem);
                      }
                      batch.update(destinationVendorRef, {'menu': updatedDestinationMenu});

                      await batch.commit();

                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Stock shifted successfully!')),
                      );
                    }
                  },
                  child: const Text('Shift'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}