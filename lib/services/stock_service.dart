import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Constants for stock management
const int STOCK_HISTORY_PRUNE_DAYS = 60;
const int VENDOR_ID_LENGTH = 6;

class StockService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Updates the user's stock and manages stock history.
  ///
  /// This method handles:
  /// 1. Calculating stock changes based on user input.
  /// 2. Updating the main vendor document with new stock values.
  /// 3. Saving daily stock data to a history collection.
  /// 4. Pruning old stock history data (older than [STOCK_HISTORY_PRUNE_DAYS] days).
  Future<void> updateUserStock(
    String userId,
    List<Map<String, dynamic>> editingMenuItems,
    List<Map<String, dynamic>> menuItems,
    List<TextEditingController> stockControllers,
  ) async {
    WriteBatch batch = _firestore.batch();

    // Update totalStockUpdates for edited items based on how stock changed
    for (int i = 0; i < editingMenuItems.length; i++) {
      final editedItem = editingMenuItems[i];
      final originalItem = menuItems[i]; // Assuming menuItems is up-to-date with fetched data

      final int originalStockValue = (originalItem['stock'] as num?)?.toInt() ?? 0;
      
      // Read quantity to add from controller
      int quantityToAdd = int.tryParse(stockControllers[i].text) ?? 0;

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

    // Reference to the vendor's document
    DocumentReference vendorRef = _firestore.collection('vendors').doc(userId);
    batch.update(vendorRef, {
      'menu': editingMenuItems.map((item) {
        return {
          ...item,
          'date': item['date'] is DateTime ? Timestamp.fromDate(item['date'] as DateTime) : item['date'],
          'totalStockAdded': item['todayStockAdded'] ?? 0,
          'todayStockSold': item['todayStockSold'] ?? 0,
          'totalStockUpdates': item['totalStockUpdates'] ?? 0,
        };
      }).toList(),
    });

    // Save daily stock history
    String todayDateString = DateTime.now().toIso8601String().split('T')[0];
    DocumentReference stockHistoryRef = _firestore.collection('vendor_stock_history').doc(userId);
    
    // Prune data older than STOCK_HISTORY_PRUNE_DAYS
    DocumentSnapshot stockHistorySnapshot = await stockHistoryRef.get();
    if (stockHistorySnapshot.exists) {
      Map<String, dynamic> stockHistoryData = stockHistorySnapshot.data() as Map<String, dynamic>;
      Map<String, dynamic> updatedStockHistoryData = {};
      DateTime today = DateTime.now();
      DateTime sixtyDaysAgo = today.subtract(const Duration(days: STOCK_HISTORY_PRUNE_DAYS));

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
      todayDateString: editingMenuItems.map((item) {
        return {
          ...item,
          'date': item['date'] is DateTime ? Timestamp.fromDate(item['date'] as DateTime) : item['date'],
        };
      }).toList(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Displays a dialog for shifting stock to another vendor.
  ///
  /// This method handles:
  /// 1. Validating user input for quantity and destination vendor ID.
  /// 2. Updating stock for both source and destination vendors in a batch.n  /// 3. Providing user feedback via Snackbars.
  Future<void> shiftStock(
    BuildContext context,
    List<Map<String, dynamic>> menuItems,
  ) async {
    final _shiftFormKey = GlobalKey<FormState>();
    List<TextEditingController> _shiftControllers = List.generate(menuItems.length, (index) => TextEditingController());
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
                          itemCount: menuItems.length,
                          itemBuilder: (context, index) {
                            final item = menuItems[index];
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
                          if (val == null || val.isEmpty || val.length != VENDOR_ID_LENGTH) {
                            return 'Enter a ${VENDOR_ID_LENGTH}-digit ID';
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
                      final querySnapshot = await _firestore
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

                      WriteBatch batch = _firestore.batch();

                      // Update source vendor
                      DocumentReference sourceVendorRef = _firestore.collection('vendors').doc(sourceUser.uid);
                      List<Map<String, dynamic>> updatedSourceMenu = [];
                      for (int i = 0; i < menuItems.length; i++) {
                        final item = Map<String, dynamic>.from(menuItems[i]);
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
                        int sourceItemIndex = menuItems.indexWhere((srcItem) => srcItem['name'] == destItem['name']);
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
