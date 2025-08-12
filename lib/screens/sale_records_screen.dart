import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:path_provider/path_provider.dart'; // For temporary directory
import 'package:share_plus/share_plus.dart'; // For sharing files
import 'dart:io'; // For File operations

import 'package:pdf/widgets.dart' as pw;

import 'package:flutter/services.dart'; // Required for rootBundle

class SaleRecordsScreen extends StatefulWidget {
  const SaleRecordsScreen({Key? key}) : super(key: key);

  @override
  State<SaleRecordsScreen> createState() => _SaleRecordsScreenState();
}

class _SaleRecordsScreenState extends State<SaleRecordsScreen> {
  String? _currentUserUid;
  List<Map<String, dynamic>> _monthlyRecords = [];
  bool _isLoading = true;
  bool _showThisMonth = true; // true for this month, false for last month

  @override
  void initState() {
    super.initState();
    _getCurrentUserUid();
  }

  /// Fetches the current user's UID and then initiates fetching of sale records.
  void _getCurrentUserUid() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _currentUserUid = user.uid;
      });
      _fetchSaleRecords();
    }
  }

  /// Fetches sale records for the current or last month from Firestore.
  ///
  /// Aggregates daily stock data and prunes old records.
  Future<void> _fetchSaleRecords() async {
    if (_currentUserUid == null) return;

    setState(() {
      _isLoading = true;
      _monthlyRecords = [];
    });

    DateTime now = DateTime.now();
    DateTime startDate;
    DateTime endDate;

    // Determine the date range based on whether to show this month or last month's records
    if (_showThisMonth) {
      startDate =
          DateTime(now.year, now.month, 1); // First day of current month
      endDate =
          DateTime(now.year, now.month + 1, 0); // Last day of current month
    } else {
      startDate =
          DateTime(now.year, now.month - 1, 1); // First day of previous month
      endDate = DateTime(now.year, now.month, 0); // Last day of previous month
    }

    try {
      DocumentSnapshot vendorHistoryDoc = await FirebaseFirestore.instance
          .collection('vendor_stock_history')
          .doc(_currentUserUid)
          .get();

      if (vendorHistoryDoc.exists) {
        Map<String, dynamic> historyData = vendorHistoryDoc.data() as Map<
            String,
            dynamic>;
        Map<String, Map<String, dynamic>> dailyAggregates = {};

        historyData.forEach((dateString, dailyItems) {
          try {
            DateTime recordDate = DateTime.parse(dateString);
            // Filter records within the selected month
            if (recordDate.isAfter(startDate.subtract(Duration(days: 1))) &&
                recordDate.isBefore(endDate.add(Duration(days: 1)))) {
              int totalStockAdded = 0;
              int totalPlatesSold = 0;
              int totalPlatesRemaining = 0;
              int totalPlatesShifted = 0;

              if (dailyItems is List) {
                for (var item in dailyItems) {
                  totalStockAdded +=
                      (item['todayStockAdded'] as num?)?.toInt() ?? 0;
                  totalPlatesSold +=
                      (item['todayStockSold'] as num?)?.toInt() ?? 0;
                  totalPlatesRemaining += (item['stock'] as num?)?.toInt() ?? 0;
                  totalPlatesShifted +=
                      (item['stockShiftedToday'] as num?)?.toInt() ?? 0;
                }
              }

              dailyAggregates[dateString] = {
                'date': recordDate,
                'totalStockAdded': totalStockAdded,
                'totalPlatesSold': totalPlatesSold,
                'totalPlatesRemaining': totalPlatesRemaining,
                'totalPlatesShifted': totalPlatesShifted,
                'incentive': 0, // Always 0 for now
              };
            }
          } catch (e) {
            print('Error parsing date or item data: $e');
          }
        });

        // Sort records by date
        _monthlyRecords = dailyAggregates.values.toList()
          ..sort((a, b) =>
              (a['date'] as DateTime).compareTo(b['date'] as DateTime));
      }
    } catch (e) {
      print('Error fetching sale records: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching sale records: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _generateAndDownloadPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showThisMonth = true;
                    });
                    _fetchSaleRecords();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _showThisMonth ? Theme
                        .of(context)
                        .primaryColor : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('This Month'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showThisMonth = false;
                    });
                    _fetchSaleRecords();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !_showThisMonth ? Theme
                        .of(context)
                        .primaryColor : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Last Month'),
                ),
              ],
            ),
          ),
          _isLoading
              ? const Expanded(
              child: Center(child: CircularProgressIndicator()))
              : _monthlyRecords.isEmpty
              ? const Expanded(
              child: Center(child: Text('No records found for this period.')))
              : Expanded(
            child: ListView.builder(
              itemCount: _monthlyRecords.length,
              itemBuilder: (context, index) {
                final record = _monthlyRecords[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 4.0),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Date: ${DateFormat('yyyy-MM-dd').format(
                              record['date'])}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        _buildRecordRow(
                            'Total Stock Added:', record['totalStockAdded']
                            .toString()),
                        _buildRecordRow(
                            'Plates Sold:', record['totalPlatesSold']
                            .toString()),
                        _buildRecordRow(
                            'Plates Remaining:', record['totalPlatesRemaining']
                            .toString()),
                        _buildRecordRow(
                            'Plates Shifted:', record['totalPlatesShifted']
                            .toString()),
                        _buildRecordRow('Incentive:', record['incentive']
                            .toString()),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(value, style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  /// Generates and shares a PDF of the sale records.
  Future<void> _generateAndDownloadPdf() async {
    if (_currentUserUid == null || _monthlyRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No records to share or user not logged in.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      // Fetch vendor details for the PDF header
      DocumentSnapshot vendorDoc = await FirebaseFirestore.instance.collection(
          'vendors').doc(_currentUserUid).get();
      String vendorName = vendorDoc['name'] ?? 'N/A';
      String vendorUniqueId = vendorDoc['uniqueId'] ?? 'N/A';

      final pdf = pw.Document();

      // Load a font that supports Unicode characters (e.g., Roboto)
      final fontData = await rootBundle.load("assets/fonts/Roboto-Regular.ttf");
      final ttf = pw.Font.ttf(fontData);

      // Prepare table data for the PDF
      List<List<String>> tableData = [
        [
          'Date',
          'Stock Added',
          'Plates Sold',
          'Plates Remaining',
          'Plates Shifted',
          'Incentive'
        ]
      ];
      for (var record in _monthlyRecords) {
        tableData.add([
          DateFormat('yyyy-MM-dd').format(record['date']),
          record['totalStockAdded'].toString(),
          record['totalPlatesSold'].toString(),
          record['totalPlatesRemaining'].toString(),
          record['totalPlatesShifted'].toString(),
          record['incentive'].toString(),
        ]);
      }

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Vendor Name: $vendorName', style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold, font: ttf)),
                pw.Text('Vendor ID: $vendorUniqueId',
                    style: pw.TextStyle(fontSize: 16, font: ttf)),
                pw.SizedBox(height: 20),
                pw.Text('Sale Records for ${_showThisMonth
                    ? 'This Month'
                    : 'Last Month'}', style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold, font: ttf)),
                pw.SizedBox(height: 10),
                pw.TableHelper.fromTextArray(
                  headers: tableData[0],
                  data: tableData.sublist(1),
                  border: pw.TableBorder.all(),
                  headerStyle: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, font: ttf),
                  cellAlignment: pw.Alignment.center,
                  cellStyle: pw.TextStyle(font: ttf),
                ),
              ],
            );
          },
        ),
      );

      // Define the file name
      final String fileName = 'sale_records_${DateFormat('yyyy-MM').format(
          DateTime.now())}.pdf';
      final Uint8List pdfBytes = await pdf.save();

      // Get temporary directory
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      // Share the file
      await Share.shareXFiles([XFile(filePath)], text: 'Here are the sale records.');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sale records shared successfully!')),
      );
    } catch (e) {
      print('Error generating or sharing PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share records: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}