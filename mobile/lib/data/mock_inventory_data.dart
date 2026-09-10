import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MockInventoryItem {
  const MockInventoryItem({
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sku': sku,
        'category': category,
        'quantity': quantity,
        'unit': unit,
        'reorderLevel': reorderLevel,
        'unitCost': unitCost,
        'branch': branch,
      };

  factory MockInventoryItem.fromJson(Map<String, dynamic> json) =>
      MockInventoryItem(
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

  MockInventoryItem copyWith({double? quantity}) => MockInventoryItem(
        id: id,
        name: name,
        sku: sku,
        category: category,
        quantity: quantity ?? this.quantity,
        unit: unit,
        reorderLevel: reorderLevel,
        unitCost: unitCost,
        branch: branch,
      );
}

class MockPurchaseOrder {
  MockPurchaseOrder({
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

  bool approving = false;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'supplier': supplier,
        'branch': branch,
        'status': status,
        'amount': amount,
        'lineItems': lineItems,
        'createdAt': createdAt,
      };

  factory MockPurchaseOrder.fromJson(Map<String, dynamic> json) =>
      MockPurchaseOrder(
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

class MockInventoryData {
  static const _storageKeyItems = 'upgradehub.mobile.mock_items';
  static const _storageKeyOrders = 'upgradehub.mobile.mock_orders';

  static final List<MockInventoryItem> defaultItems = [
    const MockInventoryItem(
      id: 'item-1',
      name: 'Premium Coffee Beans',
      sku: 'SKU-00132',
      category: 'Raw Materials',
      quantity: 6,
      unit: 'kg',
      reorderLevel: 40,
      unitCost: 3850,
      branch: 'Main branch',
    ),
    const MockInventoryItem(
      id: 'item-2',
      name: 'Vanilla Syrup 750ml',
      sku: 'SKU-00324',
      category: 'Ingredients',
      quantity: 0,
      unit: 'bottles',
      reorderLevel: 25,
      unitCost: 2400,
      branch: 'Main branch',
    ),
    const MockInventoryItem(
      id: 'item-3',
      name: 'Whole Milk 1L (Small)',
      sku: 'SKU-00811',
      category: 'Dairy',
      quantity: 18,
      unit: 'cartons',
      reorderLevel: 80,
      unitCost: 480,
      branch: 'Main branch',
    ),
    const MockInventoryItem(
      id: 'item-4',
      name: 'Packaging Boxes — Medium',
      sku: 'SKU-00598',
      category: 'Packaging',
      quantity: 11,
      unit: 'boxes',
      reorderLevel: 60,
      unitCost: 120,
      branch: 'Colombo outlet',
    ),
    const MockInventoryItem(
      id: 'item-5',
      name: 'Craft Paper Cups 12oz (x50)',
      sku: 'SKU-00612',
      category: 'Packaging',
      quantity: 24,
      unit: 'packs',
      reorderLevel: 40,
      unitCost: 850,
      branch: 'Kandy outlet',
    ),
    const MockInventoryItem(
      id: 'item-6',
      name: 'Brown Sugar 500g',
      sku: 'SKU-00902',
      category: 'Ingredients',
      quantity: 17,
      unit: 'bags',
      reorderLevel: 30,
      unitCost: 320,
      branch: 'Galle outlet',
    ),
  ];

  static final List<MockPurchaseOrder> defaultOrders = [
    MockPurchaseOrder(
      id: 'po-2141',
      number: 'PO-2141',
      supplier: 'Flour & Co Bakery Supply',
      branch: 'Main branch',
      status: 'InReview',
      amount: 61400,
      lineItems: 4,
      createdAt: '2026-08-04T13:10:00Z',
    ),
    MockPurchaseOrder(
      id: 'po-2144',
      number: 'PO-2144',
      supplier: 'Fresh Farms Dairy',
      branch: 'Main branch',
      status: 'Placed',
      amount: 72850,
      lineItems: 1,
      createdAt: '2026-08-05T07:45:00Z',
    ),
    MockPurchaseOrder(
      id: 'po-2147',
      number: 'PO-2147',
      supplier: 'Ceylon Coffee Traders',
      branch: 'Main branch',
      status: 'InTransit',
      amount: 184500,
      lineItems: 3,
      createdAt: '2026-08-08T10:00:00Z',
    ),
    MockPurchaseOrder(
      id: 'po-2146',
      number: 'PO-2146',
      supplier: 'MetroPack Ltd',
      branch: 'Main branch',
      status: 'Received',
      amount: 96200,
      lineItems: 2,
      createdAt: '2026-08-06T08:30:00Z',
    ),
  ];

  static Future<List<MockInventoryItem>> getItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKeyItems);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        return list.map((e) => MockInventoryItem.fromJson(e)).toList();
      }
    } catch (_) {}
    return List.from(defaultItems);
  }

  static Future<void> saveItems(List<MockInventoryItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKeyItems, jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<MockInventoryItem?> updateQuantity(
      String sku, double delta) async {
    final items = await getItems();
    final index = items.indexWhere((it) => it.sku.toLowerCase() == sku.toLowerCase());
    if (index == -1) return null;
    final updated = items[index].copyWith(
      quantity: (items[index].quantity + delta).clamp(0, 999999).toDouble(),
    );
    items[index] = updated;
    await saveItems(items);
    return updated;
  }

  static Future<MockInventoryItem?> setCount(String sku, double count) async {
    final items = await getItems();
    final index = items.indexWhere((it) => it.sku.toLowerCase() == sku.toLowerCase());
    if (index == -1) return null;
    final updated = items[index].copyWith(quantity: count);
    items[index] = updated;
    await saveItems(items);
    return updated;
  }

  static Future<List<MockPurchaseOrder>> getOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKeyOrders);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        return list.map((e) => MockPurchaseOrder.fromJson(e)).toList();
      }
    } catch (_) {}
    return List.from(defaultOrders);
  }

  static Future<void> saveOrders(List<MockPurchaseOrder> orders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKeyOrders, jsonEncode(orders.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<bool> approveOrder(String id) async {
    final orders = await getOrders();
    final index = orders.indexWhere((it) => it.id == id);
    if (index == -1) return false;
    orders[index].status = 'Placed';
    await saveOrders(orders);
    return true;
  }
}
