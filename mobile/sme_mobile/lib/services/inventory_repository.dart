import 'package:dio/dio.dart';

import '../models/inventory_models.dart';

/// Stock, movements and procurement — the mobile twin of the web app's
/// Inventory section. Branch scoping is applied server-side from the JWT,
/// so a branch id is only ever passed when the operator deliberately
/// narrows the view.
class InventoryRepository {
  final Dio _dio;
  const InventoryRepository(this._dio);

  static List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) from) {
    final raw = data is Map<String, dynamic> ? (data['items'] as List<dynamic>? ?? const []) : (data as List<dynamic>);
    return raw.map((e) => from(e as Map<String, dynamic>)).toList();
  }

  Future<List<InventoryItem>> items({String? branchId, String? search, String? status, int pageSize = 200}) async {
    final response = await _dio.get('/inventory', queryParameters: {
      'page': 1,
      'pageSize': pageSize,
      if (branchId != null) 'branchId': branchId,
      if (search != null && search.isNotEmpty) 'search': search,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return _list(response.data, InventoryItem.fromJson);
  }

  Future<List<InventoryItem>> lowStock({int pageSize = 100}) async {
    final response = await _dio.get('/inventory/low-stock', queryParameters: {'pageSize': pageSize});
    return _list(response.data, InventoryItem.fromJson);
  }

  Future<List<StockMovement>> movements({String? itemId, int pageSize = 150}) async {
    final response = await _dio.get('/inventory/movements', queryParameters: {
      'pageSize': pageSize,
      if (itemId != null) 'inventoryItemId': itemId,
    });
    return _list(response.data, StockMovement.fromJson);
  }

  Future<void> createItem({
    required String name,
    required String sku,
    String? description,
    String? categoryId,
    String? unitId,
    String? branchId,
    double quantity = 0,
    double reorderLevel = 0,
    double? unitCost,
  }) =>
      _dio.post('/inventory', data: {
        'name': name,
        'sku': sku,
        'description': description,
        'categoryId': categoryId,
        'unitId': unitId,
        'branchId': branchId,
        'quantity': quantity,
        'reorderLevel': reorderLevel,
        'unitCost': unitCost,
      });

  Future<void> updateItem(
    String id, {
    String? name,
    String? sku,
    String? description,
    String? categoryId,
    String? unitId,
    String? branchId,
    double reorderLevel = 0,
    double? unitCost,
  }) =>
      _dio.put('/inventory/$id', data: {
        'name': name,
        'sku': sku,
        'description': description,
        'categoryId': categoryId,
        'unitId': unitId,
        'branchId': branchId,
        'reorderLevel': reorderLevel,
        'unitCost': unitCost,
      });

  Future<void> deleteItem(String id) => _dio.delete('/inventory/$id');

  /// A correction, signed: a negative quantity takes stock off.
  Future<void> adjust(String id, double quantity, {String? reference, String? notes}) =>
      _dio.post('/inventory/$id/adjust', data: {'quantity': quantity, 'reference': reference, 'notes': notes});

  Future<void> receive(String id, double quantity, {double? unitCost, String? reference, String? notes}) =>
      _dio.post('/inventory/$id/receive',
          data: {'quantity': quantity, 'unitCost': unitCost, 'reference': reference, 'notes': notes});

  Future<void> waste(String id, double quantity, {String? reason, String? reference, String? notes}) =>
      _dio.post('/inventory/$id/waste',
          data: {'quantity': quantity, 'reason': reason, 'reference': reference, 'notes': notes});

  // ── Purchase orders ───────────────────────────────────────────────────

  Future<List<PurchaseOrder>> purchaseOrders({String? branchId, String? supplierId, String? status}) async {
    final response = await _dio.get('/purchase-orders', queryParameters: {
      'page': 1,
      'pageSize': 100,
      if (branchId != null) 'branchId': branchId,
      if (supplierId != null) 'supplierId': supplierId,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    return _list(response.data, PurchaseOrder.fromJson);
  }

  Future<PurchaseOrderOptions> purchaseOrderOptions() async {
    final response = await _dio.get('/purchase-orders/options');
    return PurchaseOrderOptions.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> createPurchaseOrder({
    required String branchId,
    required String supplierId,
    String? number,
    String? status,
    required List<PurchaseOrderLine> lines,
  }) =>
      _dio.post('/purchase-orders', data: {
        'branchId': branchId,
        'supplierId': supplierId,
        'number': number,
        'status': status,
        'items': lines.map((l) => l.toJson()).toList(),
      });

  Future<void> setPurchaseOrderStatus(String id, String status) =>
      _dio.put('/purchase-orders/$id/status', data: {'status': status});

  // ── Analytics ─────────────────────────────────────────────────────────

  Future<InventoryUsageReport> usage({String? branchId}) async {
    final response = await _dio.get('/reports/inventory-usage', queryParameters: {
      if (branchId != null) 'branchId': branchId,
    });
    return InventoryUsageReport.fromJson(response.data as Map<String, dynamic>);
  }
}
