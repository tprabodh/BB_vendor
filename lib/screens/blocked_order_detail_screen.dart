import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class BlockedOrderDetailScreen extends StatelessWidget {
  final String blockedOrderId;

  const BlockedOrderDetailScreen({super.key, required this.blockedOrderId});

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      await launchUrl(launchUri);
    } catch (e) {
      // TODO: Implement proper logging instead of print
      // print('Could not launch phone dialer: $e');
    }
  }

  Future<void> _launchGoogleMaps(GeoPoint location) async {
    final String googleMapsUrl =
        'https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}';
    final Uri launchUri = Uri.parse(googleMapsUrl);
    try {
      await launchUrl(launchUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      // TODO: Implement proper logging instead of print
      // print('Could not launch Google Maps: $e');
    }
  }

  Future<void> _closeOrder(BuildContext context) async {
    try {
      await FirebaseFirestore.instance.collection('blocked_items').doc(blockedOrderId).update({'closed': true});
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order closed successfully!')),
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Go back to the previous screen
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to close order: $e')),
      );
    }
  }

  Future<void> _showCloseConfirmationDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Close'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Are you sure you want to close this order?'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
                _closeOrder(context);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Blocked Order Details',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blue,
        elevation: 5.0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _fetchOrderDetails(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            if (!snapshot.hasData) {
              return const Center(child: Text('Blocked Order not found.'));
            }

            var orderData = snapshot.data!['orderData'] as Map<String, dynamic>;
            var customerData =
            snapshot.data!['customerData'] as Map<String, dynamic>;

            String customerName = orderData['customerName'] ?? 'N/A';
            String customerPhoneNumber = orderData['customerPhoneNumber'] ?? 'N/A';
            String customerAddress = orderData['address'] ?? customerData['address'] ?? 'N/A';
            String customerLandmark = orderData['landmark'] ?? customerData['landmark'] ?? 'N/A';
            bool newLocation = orderData['new_location'] ?? false;
            GeoPoint? location = orderData['location'];
            List<dynamic> blockedItems = orderData['blockedItems'] ?? [];
            Timestamp timestamp = orderData['timestamp'] ?? Timestamp.now();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customer Details',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900),
                          ),
                          const Divider(height: 20, thickness: 1),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Name:',
                                  style: Theme.of(context).textTheme.titleMedium),
                              Text(customerName,
                                  style: Theme.of(context).textTheme.bodyLarge),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Blocked On:',
                                  style: Theme.of(context).textTheme.titleMedium),
                              Text(
                                timestamp.toDate().toLocal().toString().split('.')[0],
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Phone:',
                                  style: Theme.of(context).textTheme.titleMedium),
                              ElevatedButton.icon(
                                onPressed: () => _makePhoneCall(customerPhoneNumber),
                                icon: const Icon(Icons.call),
                                label: const Text('Call Customer'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                          if (!newLocation) ...[
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Address:',
                                    style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(customerAddress,
                                      style: Theme.of(context).textTheme.bodyLarge,
                                      textAlign: TextAlign.end),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Landmark:',
                                    style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(customerLandmark,
                                      style: Theme.of(context).textTheme.bodyLarge,
                                      textAlign: TextAlign.end),
                                ),
                              ],
                            ),
                          ],
                          if (location != null) ...[
                            const SizedBox(height: 20),
                            Center(
                              child: ElevatedButton.icon(
                                onPressed: () => _launchGoogleMaps(location),
                                icon: const Icon(Icons.map),
                                label: const Text('View on Google Maps'),
                                style: ElevatedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.only(bottom: 20),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Blocked Items',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900),
                          ),
                          const Divider(height: 20, thickness: 1),
                          blockedItems.isEmpty
                              ? const Text('No blocked items.')
                              : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: blockedItems.length,
                            itemBuilder: (context, index) {
                              var item = blockedItems[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8.0),
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item['itemName']} (Qty: ${item['quantity']})',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                        'MRP: Rs.${(item['mrp'] ?? 0.0).toStringAsFixed(2)}'),
                                    Text(
                                        'Selling Price: Rs.${(item['sellingPrice'] ?? 0.0).toStringAsFixed(2)}'),
                                    Text(
                                        'Description: ${item['description'] ?? 'N/A'}'),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _showCloseConfirmationDialog(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                      child: const Text('Close This Order'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchOrderDetails() async {
    DocumentSnapshot orderDoc = await FirebaseFirestore.instance
        .collection('blocked_items')
        .doc(blockedOrderId)
        .get();

    if (!orderDoc.exists) {
      throw Exception('Blocked Order not found.');
    }

    var orderData = orderDoc.data() as Map<String, dynamic>;
    String customerId = orderData['customerId'];

    DocumentSnapshot customerDoc = await FirebaseFirestore.instance
        .collection('customers')
        .doc(customerId)
        .get();

    if (!customerDoc.exists) {
      throw Exception('Customer not found.');
    }

    var customerData = customerDoc.data() as Map<String, dynamic>;

    return {
      'orderData': orderData,
      'customerData': customerData,
    };
  }
}