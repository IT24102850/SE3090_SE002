/// Inventory & procurement models — the mobile twin of the web app's
/// Inventory section (manager, movements, purchase orders, low-stock
/// alerts, branch overview and analytics).
library;

double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
int _i(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class InventoryItem {
  final String id;
  final String name;
  final String sku;
  final String? description;
  final String? categoryId;
  final String category;
  final String? unitId;
  final String unit;
  final String? branchId;
  final String branch;
  final double quantity;
  final double reorderLevel;
  final double unitCost;
  final String status;
  final DateTime? createdAt;

  const InventoryItem({
    required this.id,
    required this.name,
    required this.sku,
    this.description,
    this.categoryId,
    required this.category,
    this.unitId,
    required this.unit,
    this.branchId,
    required this.branch,
    required this.quantity,
    required this.reorderLevel,
    required this.unitCost,
    required this.status,
    this.createdAt,
  });

  /// Stock value on hand, which is what the analytics tiles total.
  double get stockValue => quantity * unitCost;

  bool get isLow => quantity <= reorderLevel;
  bool get isOut => quantity <= 0;

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        sku: (j['sku'] ?? '').toString(),
        description: j['description']?.toString(),
        categoryId: j['categoryId']?.toString(),
        category: (j['category'] ?? 'Uncategorised').toString(),
        unitId: j['unitId']?.toString(),
        unit: (j['unit'] ?? '').toString(),
        branchId: j['branchId']?.toString(),
        branch: (j['branch'] ?? '—').toString(),
        quantity: _d(j['quantity']),
        reorderLevel: _d(j['reorderLevel']),
        unitCost: _d(j['unitCost']),
        status: (j['status'] ?? '').toString(),
        createdAt: _dt(j['createdAt']),
      );
}

class StockMovement {
  final String id;
  final DateTime? occurredAt;
  final String item;
  final String sku;
  final String movementType;
  final double quantity;
  final String? reference;
  final String? notes;

  const StockMovement({
    required this.id,
    this.occurredAt,
    required this.item,
    required this.sku,
    required this.movementType,
    required this.quantity,
    this.reference,
    this.notes,
  });

  bool get isInbound => quantity >= 0;

  factory StockMovement.fromJson(Map<String, dynamic> j) => StockMovement(
        id: j['id'].toString(),
        occurredAt: _dt(j['occurredAt']),
        item: (j['item'] ?? '').toString(),
        sku: (j['sku'] ?? '').toString(),
        movementType: (j['movementType'] ?? '').toString(),
        quantity: _d(j['quantity']),
        reference: j['reference']?.toString(),
        notes: j['notes']?.toString(),
      );
}

class PurchaseOrderLine {
  final String? inventoryItemId;
  final String itemName;
  final String? sku;
  final double quantity;
  final double unitCost;

  const PurchaseOrderLine({
    this.inventoryItemId,
    required this.itemName,
    this.sku,
    required this.quantity,
    required this.unitCost,
  });

  double get lineTotal => quantity * unitCost;

  factory PurchaseOrderLine.fromJson(Map<String, dynamic> j) => PurchaseOrderLine(
        inventoryItemId: j['inventoryItemId']?.toString(),
        itemName: (j['itemName'] ?? j['item'] ?? '').toString(),
        sku: j['sku']?.toString(),
        quantity: _d(j['quantity']),
        unitCost: _d(j['unitPrice'] ?? j['unitCost']),
      );

  Map<String, dynamic> toJson() => {
        'inventoryItemId': inventoryItemId,
        'description': itemName,
        'quantity': quantity,
        'unitPrice': unitCost,
      };
}

class PurchaseOrder {
  final String id;
  final String orderNumber;
  final String status;
  final String? supplierId;
  final String supplier;
  final String? branchId;
  final String branch;
  final DateTime? orderedAt;
  final DateTime? expectedAt;
  final DateTime? receivedAt;
  final double totalCost;
  final String? notes;
  final int lineItemCount;
  final List<PurchaseOrderLine> lines;

  const PurchaseOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    this.supplierId,
    required this.supplier,
    this.branchId,
    required this.branch,
    this.orderedAt,
    this.expectedAt,
    this.receivedAt,
    required this.totalCost,
    this.notes,
    required this.lineItemCount,
    required this.lines,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> j) => PurchaseOrder(
        id: j['id'].toString(),
        orderNumber: (j['number'] ?? j['orderNumber'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        supplierId: j['supplierId']?.toString(),
        supplier: (j['supplier'] ?? j['supplierName'] ?? '—').toString(),
        branchId: j['branchId']?.toString(),
        branch: (j['branch'] ?? j['branchName'] ?? '—').toString(),
        orderedAt: _dt(j['createdAt'] ?? j['orderedAt']),
        expectedAt: _dt(j['expectedAt'] ?? j['expectedDate']),
        receivedAt: _dt(j['receivedAt']),
        totalCost: _d(j['totalAmount'] ?? j['totalCost']),
        notes: j['notes']?.toString(),
        lineItemCount: _i(j['lineItems']),
        lines: ((j['items'] ?? j['lines']) as List<dynamic>? ?? [])
            .map((l) => PurchaseOrderLine.fromJson(l as Map<String, dynamic>))
            .toList(),
      );
}

/// A named id from GET /purchase-orders/options — branches, suppliers and
/// the items a line can be raised against.
class NamedOption {
  final String id;
  final String name;
  final String? sku;
  final double unitCost;
  final String? branchId;

  const NamedOption({required this.id, required this.name, this.sku, this.unitCost = 0, this.branchId});

  factory NamedOption.fromJson(Map<String, dynamic> j) => NamedOption(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        sku: j['sku']?.toString(),
        unitCost: _d(j['unitCost']),
        branchId: j['branchId']?.toString(),
      );
}

class PurchaseOrderOptions {
  final List<NamedOption> branches;
  final List<NamedOption> suppliers;
  final List<NamedOption> items;

  const PurchaseOrderOptions({required this.branches, required this.suppliers, required this.items});

  static List<NamedOption> _list(dynamic v) =>
      ((v as List<dynamic>?) ?? []).map((e) => NamedOption.fromJson(e as Map<String, dynamic>)).toList();

  factory PurchaseOrderOptions.fromJson(Map<String, dynamic> j) => PurchaseOrderOptions(
        branches: _list(j['branches']),
        suppliers: _list(j['suppliers']),
        items: _list(j['items']),
      );
}

/// GET /reports/inventory-usage — what the analytics screen charts.
class InventoryUsageRow {
  final String itemName;
  final String sku;
  final double received;
  final double issued;
  final double net;
  final int movementCount;

  const InventoryUsageRow({
    required this.itemName,
    required this.sku,
    required this.received,
    required this.issued,
    required this.net,
    required this.movementCount,
  });

  factory InventoryUsageRow.fromJson(Map<String, dynamic> j) => InventoryUsageRow(
        itemName: (j['itemName'] ?? '').toString(),
        sku: (j['sku'] ?? '').toString(),
        received: _d(j['receivedQuantity']),
        issued: _d(j['issuedQuantity']),
        net: _d(j['netQuantity']),
        movementCount: _i(j['movementCount']),
      );
}

class InventoryUsageReport {
  final double totalReceived;
  final double totalIssued;
  final double net;
  final List<InventoryUsageRow> items;

  const InventoryUsageReport({
    required this.totalReceived,
    required this.totalIssued,
    required this.net,
    required this.items,
  });

  factory InventoryUsageReport.fromJson(Map<String, dynamic> j) => InventoryUsageReport(
        totalReceived: _d(j['totalReceivedQuantity']),
        totalIssued: _d(j['totalIssuedQuantity']),
        net: _d(j['netQuantity']),
        items: ((j['items'] as List<dynamic>?) ?? [])
            .map((e) => InventoryUsageRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
