# Mobile inventory app

This Flutter scaffold shares the web client's login contract:

- `POST /api/auth/login` with `{ "email", "password" }`.
- Response containing `accessToken` or `token`.
- JWT roles: `Admin`, `Manager`, and `Staff`; plus `tenant_id`.

Tokens are stored with `flutter_secure_storage`, using Android encrypted shared
preferences and the iOS Keychain. The app clears expired or malformed tokens on
startup. It never stores passwords.

Authenticated inventory feature screens should obtain their request client from
`auth.authenticatedClient()`. The shared client adds `Authorization: Bearer
<token>` to every request; screens must never read or persist the token.

## Run

After generating platform folders with `flutter create .`, fetch packages and run
against the local API:

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5107
```

`10.0.2.2` is the Android emulator's route to the host machine. On a physical
device, replace it with the computer's LAN IP address. For an iOS simulator, use
`http://localhost:5107`.

The Android app requires a minimum SDK level of 23 for secure encrypted storage.
