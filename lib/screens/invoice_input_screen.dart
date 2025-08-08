import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InvoiceInputScreen extends StatefulWidget {
  const InvoiceInputScreen({super.key});
  @override
  State<InvoiceInputScreen> createState() => _InvoiceInputScreenState();
}

class _InvoiceInputScreenState extends State<InvoiceInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _customerIdentifierController = TextEditingController();
  final Map<String, int> _selectedQuantities = {};
  List<Map<String, dynamic>> _vendorMenuItems = [];
  String? _vendorId;
  String? _vendorName;
  String? _vendorBusinessName;
  String? _vendorPhoneNumber;
  String? _vendorEmail;
  String? _vendorFssaiCode;
  String? _vendorBusinessAddress;
  String? _vendorGstin;
  final Map<String, String> _menuImageUrls = {};

  @override
  void initState() {
    super.initState();
    _loadVendorInfoAndMenu();
  }

  Future<void> _loadVendorInfoAndMenu() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _vendorId = user.uid;
      DocumentSnapshot vendorDoc = await FirebaseFirestore.instance.collection('vendors').doc(_vendorId).get();
      if (vendorDoc.exists) {
        setState(() {
          _vendorName = vendorDoc['name'];
          _vendorBusinessName = vendorDoc['businessName'];
          _vendorPhoneNumber = vendorDoc['phoneNumber'];
          _vendorEmail = vendorDoc['email'];
          _vendorFssaiCode = vendorDoc['fssaiCode'];
          _vendorBusinessAddress = vendorDoc['businessAddress'];
          _vendorGstin = vendorDoc['gstin'];
          _vendorMenuItems = List<Map<String, dynamic>>.from(vendorDoc['menu'] ?? []);
        });

        // Fetch image URLs for menu items
        for (var item in _vendorMenuItems) {
          String itemName = item['name'];
          DocumentSnapshot imageDoc = await FirebaseFirestore.instance.collection('menu_images').doc(itemName).get();
          if (imageDoc.exists) {
            setState(() {
              _menuImageUrls[itemName] = imageDoc['imageUrl'];
            });
          }
        }
      }
    }
  }

  void _updateQuantity(String itemId, int quantity, int stock) {
    if (quantity > stock) {
      if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot select more items than available in stock.')),
        );
      return;
    }
    setState(() {
      _selectedQuantities[itemId] = quantity;
    });
  }

  Future<void> _generateInvoice() async {
    if (_formKey.currentState!.validate()) {
      String customerIdentifier = _customerIdentifierController.text.trim();
      if (customerIdentifier.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enter customer email or phone number.')),
        );
        return;
      }

      List<Map<String, dynamic>> invoiceItems = [];
      for (var entry in _selectedQuantities.entries) {
        if (entry.value > 0) {
          var item = _vendorMenuItems.firstWhere((menuItem) => menuItem['name'] == entry.key, orElse: () => <String, dynamic>{});
          invoiceItems.add({
            'itemName': item['name'],
            'quantity': entry.value,
            'sellingPrice': item['sellingPrice'],
            'mrp': item['mrp'],
            'description': item['description'],
          });
        }
      }

      if (invoiceItems.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select at least one item for the invoice.')),
        );
        return;
      }

      // Find customer details
      QuerySnapshot customerQuery;
      if (customerIdentifier.contains('@')) {
        customerQuery = await FirebaseFirestore.instance.collection('customers').where('email', isEqualTo: customerIdentifier).get();
      } else {
        customerQuery = await FirebaseFirestore.instance.collection('customers').where('phone', isEqualTo: customerIdentifier).get();
      }

      if (customerQuery.docs.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Customer not found.')),
        );
        return;
      }

      var customerData = customerQuery.docs.first.data() as Map<String, dynamic>;
      String customerId = customerQuery.docs.first.id;

      try {
        // Decrement stock and update sales metrics
        DateTime now = DateTime.now();
        DateTime today = DateTime(now.year, now.month, now.day);

        for (var item in invoiceItems) {
          var menuItem = _vendorMenuItems.firstWhere((menuItem) => menuItem['name'] == item['itemName']);

          // Ensure new fields exist and are initialized
          menuItem['todayStockSold'] = menuItem['todayStockSold'] ?? 0;
          menuItem['lastDailyResetDate'] = menuItem['lastDailyResetDate'] ?? Timestamp.fromDate(today);

          // Check for daily reset
          if (menuItem['lastDailyResetDate'] is Timestamp) {
            DateTime lastResetDate = (menuItem['lastDailyResetDate'] as Timestamp).toDate();
            DateTime lastResetDay = DateTime(lastResetDate.year, lastResetDate.month, lastResetDate.day);
            if (lastResetDay.isBefore(today)) {
              menuItem['todayStockSold'] = 0; // Reset for new day
              menuItem['lastDailyResetDate'] = Timestamp.fromDate(today);
            }
          } else {
            menuItem['todayStockSold'] = 0; // Reset if malformed
            menuItem['lastDailyResetDate'] = Timestamp.fromDate(today);
          }

          menuItem['stock'] -= item['quantity'];
          menuItem['todayStockSold'] += item['quantity'];
        }

        await FirebaseFirestore.instance.collection('vendors').doc(_vendorId).update({
          'menu': _vendorMenuItems.map((item) {
            return {
              ...item,
              'lastDailyResetDate': item['lastDailyResetDate'] is DateTime ? Timestamp.fromDate(item['lastDailyResetDate']) : item['lastDailyResetDate'],
            };
          }).toList(),
        });

        await FirebaseFirestore.instance.collection('invoices').add({
          'vendorId': _vendorId,
          'vendorName': _vendorName,
          'vendorBusinessName': _vendorBusinessName,
          'vendorPhoneNumber': _vendorPhoneNumber,
          'vendorEmail': _vendorEmail,
          'vendorFssaiCode': _vendorFssaiCode,
          'vendorBusinessAddress': _vendorBusinessAddress,
          'vendorGstin': _vendorGstin,
          'customerId': customerId,
          'customerName': customerData['name'],
          'customerPhoneNumber': customerData['phone'],
          'customerAddress': customerData['address'],
          'customerLandmark': customerData['landmark'],
          'customerEmail': customerData['email'],
          'invoiceItems': invoiceItems,
          'timestamp': FieldValue.serverTimestamp(),
        });

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invoice generated successfully!')),
        );
        _customerIdentifierController.clear();
        setState(() {
          _selectedQuantities.clear();
        });
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate invoice: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Invoice', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Customer Details (Left side)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Customer Details:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 10),
            // Customer input field
            Form(
              key: _formKey,
              child: TextFormField(
                controller: _customerIdentifierController,
                decoration: const InputDecoration(labelText: 'Customer Email or Phone Number'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter customer email or phone';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Select Items:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: _vendorMenuItems.isEmpty
                  ? const Center(child: Text('No menu items available.'))
                  : ListView.builder(
                      itemCount: _vendorMenuItems.length,
                      itemBuilder: (context, index) {
                        var item = _vendorMenuItems[index];
                        String itemName = item['name'] ?? 'N/A';
                        double mrp = (item['mrp'] ?? 0.0).toDouble();
                        double sellingPrice = (item['sellingPrice'] ?? 0.0).toDouble();
                        String description = item['description'] ?? 'No description available.';
                        int stock = item['stock'] ?? 0;
                        int currentQuantity = _selectedQuantities[itemName] ?? 0;
                        String? imageUrl = _menuImageUrls[itemName];

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                // Image or Placeholder
                                Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey[300],
                                  child: imageUrl != null
                                      ? Image.network(imageUrl, fit: BoxFit.cover)
                                      : Icon(Icons.image, size: 30, color: Colors.grey[600]),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        description,
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          Text(
                                            '₹${mrp.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                              decoration: TextDecoration.lineThrough,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            '₹${sellingPrice.toStringAsFixed(2)}',
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      Text('Stock: $stock'),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle),
                                      onPressed: currentQuantity > 0
                                          ? () => _updateQuantity(itemName, currentQuantity - 1, stock)
                                          : null,
                                    ),
                                    Text('$currentQuantity'),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle),
                                      onPressed: () => _updateQuantity(itemName, currentQuantity + 1, stock),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async { await _generateInvoice(); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('Generate Invoice'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
