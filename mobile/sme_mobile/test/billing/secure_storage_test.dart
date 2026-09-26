import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/services/payment_method_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('starts empty and the first method becomes the default', () async {
    final store = PaymentMethodStore(userId: 'u1');
    expect(await store.load(), isEmpty);
    expect(await store.defaultMethod(), isNull);

    await store.add(type: 'Card', label: 'Work Visa', last4: '4242');

    final saved = await store.load();
    expect(saved.single.display, 'Work Visa •• 4242');
    expect(saved.single.isDefault, isTrue);
  });

  test('persists to secure storage, not memory', () async {
    await PaymentMethodStore(userId: 'u1').add(type: 'PayPal', label: 'PayPal');
    // A brand-new store instance reads it back from the (mock) keychain.
    expect((await PaymentMethodStore(userId: 'u1').load()).single.type, 'PayPal');
  });

  test('keeps each user\'s methods apart', () async {
    await PaymentMethodStore(userId: 'alice').add(type: 'Card', label: 'Alice card');
    expect(await PaymentMethodStore(userId: 'bob').load(), isEmpty);
  });

  test('refuses anything that looks like a full card number', () async {
    final store = PaymentMethodStore(userId: 'u1');
    expect(() => store.add(type: 'Card', label: '4242 4242 4242 4242'), throwsA(isA<PaymentMethodValidationException>()));
    expect(() => store.add(type: 'Card', label: 'Visa', last4: '424242'), throwsA(isA<PaymentMethodValidationException>()));
    expect(() => store.add(type: 'Card', label: 'Visa', last4: '42a2'), throwsA(isA<PaymentMethodValidationException>()));
    expect(await store.load(), isEmpty);
  });

  test('rejects unknown types and blank names', () async {
    final store = PaymentMethodStore(userId: 'u1');
    expect(() => store.add(type: 'Bitcoin', label: 'Wallet'), throwsA(isA<PaymentMethodValidationException>()));
    expect(() => store.add(type: 'Card', label: '   '), throwsA(isA<PaymentMethodValidationException>()));
  });

  test('makeDefault moves the default, and removing it promotes the next one', () async {
    final store = PaymentMethodStore(userId: 'u1');
    await store.add(type: 'Card', label: 'Visa');
    await store.add(type: 'QR', label: 'LankaQR', makeDefault: true);

    var saved = await store.load();
    expect(saved.where((m) => m.isDefault).single.label, 'LankaQR');

    saved = await store.remove(saved.firstWhere((m) => m.label == 'LankaQR').id);
    expect(saved.single.label, 'Visa');
    expect(saved.single.isDefault, isTrue);
  });

  test('setDefault leaves exactly one default', () async {
    final store = PaymentMethodStore(userId: 'u1');
    await store.add(type: 'Card', label: 'Visa');
    final all = await store.add(type: 'Cash', label: 'Cash');

    final after = await store.setDefault(all.last.id);
    expect(after.where((m) => m.isDefault).map((m) => m.label), ['Cash']);
    expect((await store.defaultMethod())!.label, 'Cash');
  });

  test('a corrupt entry is discarded instead of crashing', () async {
    FlutterSecureStorage.setMockInitialValues({'payment_methods_u1': 'not json'});
    expect(await PaymentMethodStore(userId: 'u1').load(), isEmpty);
  });

  test('caps the number of saved methods', () async {
    final store = PaymentMethodStore(userId: 'u1');
    for (var i = 0; i < PaymentMethodStore.maxMethods; i++) {
      await store.add(type: 'Card', label: 'Card $i');
    }
    expect(() => store.add(type: 'Card', label: 'One too many'), throwsA(isA<PaymentMethodValidationException>()));
  });
}
