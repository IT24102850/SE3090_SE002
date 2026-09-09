import 'package:flutter_test/flutter_test.dart';
import 'package:sme_mobile/models/user_model.dart';

const _base = {
  'id': 'u1',
  'email': 'ada@example.com',
  'fullName': 'Ada Perera',
  'role': 'Customer',
  'tenantId': 't1',
};

void main() {
  group('User.profilePictureUrl', () {
    test('a blank url from the API becomes null, so no NetworkImage(\'\') is ever built', () {
      final user = User.fromJson({..._base, 'profilePictureUrl': ''});
      expect(user.profilePictureUrl, isNull);
    });

    test('a real url survives the round trip through toJson', () {
      final user = User.fromJson({..._base, 'profilePictureUrl': 'https://cdn.example.com/me.jpg'});
      expect(user.profilePictureUrl, 'https://cdn.example.com/me.jpg');
      expect(User.fromJson(user.toJson()).profilePictureUrl, 'https://cdn.example.com/me.jpg');
    });

    test('copyWith needs the explicit flag to clear the photo', () {
      final user = User.fromJson({..._base, 'profilePictureUrl': 'https://cdn.example.com/me.jpg'});
      expect(user.copyWith(fullName: 'Ada P').profilePictureUrl, 'https://cdn.example.com/me.jpg');
      expect(user.copyWith(clearProfilePicture: true).profilePictureUrl, isNull);
    });
  });
}
