// lib/models/sap_models.dart

class SAPOrderResponse {
  final List<SAPOrderHeader> orders;
  final int totalCount;

  SAPOrderResponse({required this.orders, required this.totalCount});
}

class SAPOrderHeader {
  final String vbeln;
  final String kunnr;
  final String kunnrName;
  final String vbelnContract;
  final List<SAPOrderItem> items;
  final double totalValue;
  final int itemCount;

  SAPOrderHeader({
    required this.vbeln,
    required this.kunnr,
    required this.kunnrName,
    required this.vbelnContract,
    required this.items,
    required this.totalValue,
    required this.itemCount,
  });

  factory SAPOrderHeader.fromJson(Map<String, dynamic> json) {
    // Parse items
    List<SAPOrderItem> items = [];
    if (json['items'] != null && (json['items'] as List).isNotEmpty) {
      items = (json['items'] as List)
          .map((e) => SAPOrderItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      // Create single item from this row
      items = [SAPOrderItem.fromJson(json)];
    }

    double totalVal = 0;
    for (var item in items) {
      totalVal += item.totalValue;
    }

    // Get values with fallbacks
    final vbeln = json['order_number']?.toString() ?? '';
    final kunnrName = json['customer_name']?.toString() ?? '';
    final contract = json['contract_number']?.toString() ?? '';

    print('SAPOrderHeader.fromJson - vbeln: $vbeln, customer: $kunnrName');

    return SAPOrderHeader(
      vbeln: vbeln,
      kunnr: kunnrName,
      kunnrName: kunnrName,
      vbelnContract: contract,
      items: items,
      totalValue: totalVal,
      itemCount: items.length,
    );
  }
}

class SAPOrderItem {
  final int posnr;
  final String matnr;
  final String arktx;
  final double kwmeng;
  final String vrkme;
  final double netwr;
  final double totalValue;

  SAPOrderItem({
    required this.posnr,
    required this.matnr,
    required this.arktx,
    required this.kwmeng,
    required this.vrkme,
    required this.netwr,
    required this.totalValue,
  });

  factory SAPOrderItem.fromJson(Map<String, dynamic> json) {
    final qty = double.tryParse(json['quantity']?.toString() ?? '0') ?? 0;
    final value = double.tryParse(json['net_value']?.toString() ?? '0') ?? 0;

    final matnr = json['product_code']?.toString() ?? '';
    final arktx = json['description']?.toString() ?? '';
    final vrkme = json['unit_of_measure']?.toString() ?? 'EA';
    final posnr = int.tryParse(json['item_number']?.toString() ?? '0') ?? 0;

    print('SAPOrderItem.fromJson - matnr: $matnr, arktx: $arktx, qty: $qty, value: $value');

    return SAPOrderItem(
      posnr: posnr,
      matnr: matnr,
      arktx: arktx,
      kwmeng: qty,
      vrkme: vrkme,
      netwr: value,
      totalValue: qty * value,
    );
  }
}

class SAPOrderFilter {
  final String? customerName;
  final String? orderNumber;
  final String? contractNumber;
  final String? productCode;
  final String? searchTerm;
  final double? minValue;
  final double? maxValue;
  final int page;
  final int pageSize;
  final String sortBy;
  final bool ascending;

  SAPOrderFilter({
    this.customerName,
    this.orderNumber,
    this.contractNumber,
    this.productCode,
    this.searchTerm,
    this.minValue,
    this.maxValue,
    this.page = 0,
    this.pageSize = 20,
    this.sortBy = 'order_number',
    this.ascending = true,
  });
}