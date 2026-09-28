import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class SocialCredential {
  const SocialCredential({this.idToken, this.accessToken});

  final String? idToken;
  final String? accessToken;
}

/// Native OAuth flows. OAuth client IDs are public app identifiers and are
/// supplied at build time; provider client secrets must never be shipped here.
class SocialAuthService {
  static const _googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const _googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
  static const _microsoftClientId =
      String.fromEnvironment('MICROSOFT_CLIENT_ID');
  static const _microsoftRedirectUri = String.fromEnvironment(
    'MICROSOFT_REDIRECT_URI',
    defaultValue: 'com.example.sme_mobile:/oauth2redirect',
  );

  static final GoogleSignIn _google = GoogleSignIn.instance;
  static const FlutterAppAuth _appAuth = FlutterAppAuth();
  static bool _googleInitialized = false;

  static Future<SocialCredential> signIn(String provider) async {
    switch (provider.toLowerCase()) {
      case 'google':
        return _signInWithGoogle();
      case 'microsoft':
        return _signInWithMicrosoft();
      default:
        throw const SocialAuthException(
          'Apple sign-in needs an Apple Developer account and provider setup.',
        );
    }
  }

  static Future<SocialCredential> _signInWithGoogle() async {
    if (_googleWebClientId.isEmpty) {
      throw const SocialAuthException(
        'Google sign-in is not configured yet. Add GOOGLE_WEB_CLIENT_ID to the mobile build.',
      );
    }
    if (!_googleInitialized) {
      await _google.initialize(
        serverClientId: _googleWebClientId,
        clientId: _googleIosClientId.isEmpty ? null : _googleIosClientId,
      );
      _googleInitialized = true;
    }
    final account = await _google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const SocialAuthException(
        'Google did not return an identity token. Check the OAuth client setup.',
      );
    }
    return SocialCredential(idToken: idToken);
  }

  static Future<SocialCredential> _signInWithMicrosoft() async {
    if (_microsoftClientId.isEmpty) {
      throw const SocialAuthException(
        'Microsoft sign-in is not configured yet. Add MICROSOFT_CLIENT_ID to the mobile build.',
      );
    }
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        _microsoftClientId,
        _microsoftRedirectUri,
        issuer: 'https://login.microsoftonline.com/common/v2.0',
        scopes: const [
          'openid',
          'profile',
          'email',
          'offline_access',
          'https://graph.microsoft.com/User.Read',
        ],
      ),
    );
    final accessToken = result.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const SocialAuthException(
        'Microsoft did not return an access token. Please try again.',
      );
    }
    return SocialCredential(idToken: result.idToken, accessToken: accessToken);
  }
}

class SocialAuthException implements Exception {
  const SocialAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
