/// The inventory app's read models, shaped by what /api/inventory and
/// /api/purchase-orders return.
///
/// These used to live in mock_inventory_data.dart under the names
/// MockInventoryItem and MockPurchaseOrder, next to a fake store of coffee
/// shop stock that every screen fell back to when the API was unreachable.
/// The store is gone: a stock count taken against invented quantities is
/// worse than no stock count. The models were never mock - every live
/// response was already parsed through them - so they keep their shape and
/// lose the misleading prefix.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.sku,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.reorderLevel,
    required this.unitCost,
    required this.branch,
  });

  final String id;
  final String name;
  final String sku;
  final String category;
  final double quantity;
  final String unit;
  final double reorderLevel;
  final double unitCost;
  final String branch;

  bool get isLowStock => quantity <= 0 || quantity < reorderLevel;
  double get totalValue => quantity * unitCost;

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        id: '${json['id']}',
        name: json['name'] as String? ?? 'Item',
        sku: json['sku'] as String? ?? 'SKU-00000',
        category: json['category'] as String? ?? 'General',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unit: json['unit'] as String? ?? 'units',
        reorderLevel: (json['reorderLevel'] as num?)?.toDouble() ?? 10,
        unitCost: (json['unitCost'] as num?)?.toDouble() ?? 0,
        branch: json['branch'] as String? ?? 'Main branch',
      );
}

class PurchaseOrder {
  PurchaseOrder({
    required this.id,
    required this.number,
    required this.supplier,
    required this.branch,
    required this.status,
    required this.amount,
    required this.lineItems,
    required this.createdAt,
  });

  final String id;
  final String number;
  final String supplier;
  final String branch;
  String status;
  final double amount;
  final int lineItems;
  final String createdAt;

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) => PurchaseOrder(
        id: '${json['id']}',
        number: json['number'] as String? ?? 'PO-0000',
        supplier: json['supplier'] as String? ?? 'Unknown supplier',
        branch: json['branch'] as String? ?? 'Main branch',
        status: json['status'] as String? ?? 'InReview',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        lineItems: (json['lineItems'] as num?)?.toInt() ?? 1,
        createdAt: json['createdAt'] as String? ?? '',
      );
}
