import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A payment method the customer saved for next time.
///
/// Deliberately NOT a card: the app never sees a card number (card entry
/// happens on Stripe's / PayPal's own page), so what is remembered is the
/// customer's choice - "Card via Stripe", "PayPal", "QR" - with a nickname
/// and at most the last four digits they typed to recognise it.
class SavedPaymentMethod {
  final String id;
  final String type; // Card | QR | PayPal | Cash
  final String label;
  final String? last4;
  final bool isDefault;

  const SavedPaymentMethod({
    required this.id,
    required this.type,
    required this.label,
    this.last4,
    this.isDefault = false,
  });

  SavedPaymentMethod copyWith({bool? isDefault}) =>
      SavedPaymentMethod(id: id, type: type, label: label, last4: last4, isDefault: isDefault ?? this.isDefault);

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'label': label, 'last4': last4, 'isDefault': isDefault};

  factory SavedPaymentMethod.fromJson(Map<String, dynamic> j) => SavedPaymentMethod(
        id: j['id'] as String,
        type: j['type'] as String,
        label: j['label'] as String,
        last4: j['last4'] as String?,
        isDefault: j['isDefault'] as bool? ?? false,
      );

  String get display => last4 == null ? label : '$label •• $last4';
}

class PaymentMethodValidationException implements Exception {
  final String message;
  const PaymentMethodValidationException(this.message);
  @override
  String toString() => message;
}

/// Saved payment methods in flutter_secure_storage (Keychain / encrypted
/// SharedPreferences), one list per signed-in user.
class PaymentMethodStore {
  static const types = ['Card', 'QR', 'PayPal', 'Cash'];
  static const maxMethods = 10;

  final FlutterSecureStorage _storage;
  final String _key;

  PaymentMethodStore({required String userId, FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            ),
        _key = 'payment_methods_$userId';

  Future<List<SavedPaymentMethod>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => SavedPaymentMethod.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FormatException {
      // A corrupt entry is dropped rather than crashing the payment screen.
      await _storage.delete(key: _key);
      return [];
    }
  }

  Future<SavedPaymentMethod?> defaultMethod() async {
    final all = await load();
    for (final m in all) {
      if (m.isDefault) return m;
    }
    return all.isEmpty ? null : all.first;
  }

  /// Adds a method. Rejects anything that looks like a full card number.
  Future<List<SavedPaymentMethod>> add({required String type, required String label, String? last4, bool makeDefault = false}) async {
    if (!types.contains(type)) throw PaymentMethodValidationException('Unknown payment type "$type".');
    final name = label.trim();
    if (name.isEmpty) throw const PaymentMethodValidationException('Give the method a name.');
    if (name.length > 40) throw const PaymentMethodValidationException('Keep the name under 40 characters.');
    if (RegExp(r'\d{6,}').hasMatch(name.replaceAll(' ', ''))) {
      throw const PaymentMethodValidationException('Do not store card numbers - use a nickname and the last 4 digits.');
    }
    final digits = last4?.trim();
    if (digits != null && digits.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(digits)) {
      throw const PaymentMethodValidationException('Enter exactly the last 4 digits, nothing more.');
    }

    final all = await load();
    if (all.length >= maxMethods) throw const PaymentMethodValidationException('You can save up to 10 methods.');

    final method = SavedPaymentMethod(
      id: _newId(all),
      type: type,
      label: name,
      last4: digits == null || digits.isEmpty ? null : digits,
      isDefault: makeDefault || all.isEmpty,
    );
    final next = [
      for (final m in all) makeDefault ? m.copyWith(isDefault: false) : m,
      method,
    ];
    await _write(next);
    return next;
  }

  Future<List<SavedPaymentMethod>> remove(String id) async {
    final all = await load();
    final removed = all.where((m) => m.id == id).toList();
    final next = all.where((m) => m.id != id).toList();
    // Losing the default promotes the next one.
    if (removed.any((m) => m.isDefault) && next.isNotEmpty) next[0] = next[0].copyWith(isDefault: true);
    await _write(next);
    return next;
  }

  Future<List<SavedPaymentMethod>> setDefault(String id) async {
    final next = [for (final m in await load()) m.copyWith(isDefault: m.id == id)];
    await _write(next);
    return next;
  }

  Future<void> clear() => _storage.delete(key: _key);

  static final _random = Random.secure();

  /// A timestamp alone is not unique: two saves inside one clock tick
  /// (coarse on Windows) got the same id, and remove/setDefault then hit both.
  static String _newId(List<SavedPaymentMethod> existing) {
    String id;
    do {
      id = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_random.nextInt(0x7fffffff).toRadixString(36)}';
    } while (existing.any((m) => m.id == id));
    return id;
  }

  Future<void> _write(List<SavedPaymentMethod> methods) =>
      _storage.write(key: _key, value: jsonEncode(methods.map((m) => m.toJson()).toList()));
}
