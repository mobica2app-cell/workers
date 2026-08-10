import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TestDataPage extends StatefulWidget {
  @override
  State<TestDataPage> createState() => _TestDataPageState();
}

class _TestDataPageState extends State<TestDataPage> {
  List<Map<String, dynamic>> _data = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _loading = true);
    try {
      final response = await Supabase.instance.client
          .from('sap_orders_view')
          .select('*')
          .limit(20);

      print('Fetched ${response.length} records');

      setState(() {
        _data = List<Map<String, dynamic>>.from(response);
        _loading = false;
      });
    } catch (e) {
      print('Error: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Data Test (${_data.length} records)'),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: _data.length,
        itemBuilder: (context, index) {
          final item = _data[index];
          return Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order: ${item['order_number'] ?? 'N/A'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Customer: ${item['customer_name'] ?? 'N/A'}'),
                  Text('Contract: ${item['contract_number'] ?? 'N/A'}'),
                  Text('Product: ${item['product_code'] ?? 'N/A'}'),
                  Text('Description: ${item['description'] ?? 'N/A'}'),
                  Text('Qty: ${item['quantity'] ?? 'N/A'} ${item['unit_of_measure'] ?? ''}'),
                  Text('Value: ${item['net_value'] ?? 'N/A'}'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
