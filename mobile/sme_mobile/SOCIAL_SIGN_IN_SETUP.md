# Mobile social sign-in setup

The app verifies Google ID tokens and Microsoft Graph access tokens through
the backend. OAuth client IDs are public identifiers; do not put provider
client secrets in the Flutter app or commit them.

## Google

1. In Google Cloud Console, configure the OAuth consent screen and create an
   Android OAuth client for `com.example.sme_mobile` (include the SHA-1 for
   each signing key) and an iOS OAuth client for `com.example.smeMobile`.
2. Create a Web application OAuth client. The app uses this as its server
   audience, so configure the same value on the API as
   `Authentication__Google__ClientId`.
3. Add the iOS client's reversed client ID as a URL scheme in
   `ios/Runner/Info.plist`, as required by Google's iOS SDK. Supply the web
   and iOS client IDs when building/running Flutter:

   ```powershell
   flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id> --dart-define=GOOGLE_IOS_CLIENT_ID=<ios-client-id>
   ```

The Android and iOS package IDs are temporary defaults. Update the provider
registrations and redirect schemes if those app IDs change.

## Microsoft

1. In Microsoft Entra, register a public client app that allows the account
   types you need (work/school, personal Microsoft accounts, or both).
2. Add the mobile redirect URI `com.example.sme_mobile:/oauth2redirect` to the
   app registration and grant delegated Microsoft Graph `User.Read` access.
3. The API reads the verified profile from Graph using the access token. The
   Microsoft client ID is needed in the app build:

   ```powershell
   flutter run --dart-define=MICROSOFT_CLIENT_ID=<application-client-id> --dart-define=MICROSOFT_REDIRECT_URI=com.example.sme_mobile:/oauth2redirect
   ```

The backend's Microsoft integration calls Graph and does not need a client
secret. The exact redirect URI in Entra must match the one passed to Flutter.

## Apple

Apple sign-in is intentionally unavailable until the app owner has an Apple
Developer account, a Sign in with Apple enabled app identifier, and the
required Apple provider configuration on the API. The button currently shows
that setup requirement rather than starting a broken flow.
