// lib/models/product_tracking_model.dart
class ProductTracking {
  final String productCode;
  final String section;
  final int sectionIndex;
  final String contractNumber;
  final String designOrder;

  ProductTracking({
    required this.productCode,
    required this.section,
    required this.sectionIndex,
    required this.contractNumber,
    required this.designOrder,
  });

  factory ProductTracking.fromJson(Map<String, dynamic> json) {
    return ProductTracking(
      productCode: json['product_code'] ?? '',
      section: json['section'] ?? '',
      sectionIndex: json['section_index'] ?? 0,
      contractNumber: json['contract_number'] ?? '',
      designOrder: json['design_order'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_code': productCode,
      'section': section,
      'section_index': sectionIndex,
      'contract_number': contractNumber,
      'design_order': designOrder,
    };
  }
}