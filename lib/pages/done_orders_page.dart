import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/sap_service.dart';
import 'orders_page.dart';

/// SAP Done Orders uses the exact same table UI and interactions as OrdersPage,
/// but loads all rows from sap_done_orders instead of sap_main_orders.
class DoneOrdersPage extends StatelessWidget {
  final SAPMainService? sapService;
  final dynamic loggedInEmployee;

  const DoneOrdersPage({
    super.key,
    this.sapService,
    this.loggedInEmployee,
  });

  @override
  Widget build(BuildContext context) {
    final service = sapService ?? SAPMainService(Supabase.instance.client);
    return OrdersPage(
      sapService: service,
      loggedInEmployee: loggedInEmployee,
      doneOrdersOnly: true,
    );
  }
}
