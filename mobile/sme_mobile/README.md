# Unify – Flutter Mobile (Auth Module)

Fully working **Login / Register** screens with:

- **Riverpod** (`StateNotifierProvider`) for auth state
- **flutter_secure_storage** for JWT + user persistence
- **Dio** HTTP client with automatic Bearer token injection
- Session restore on cold start
- Role-based Dashboard (Admin / Manager / Staff / Customer)

## Project structure

```
lib/
├── main.dart
├── models/
│   └── user_model.dart
├── providers/
│   └── auth_provider.dart      ← AuthState + AuthNotifier
├── screens/
│   ├── login_screen.dart
│   ├── register_screen.dart
│   └── dashboard_screen.dart
└── services/
    ├── api_service.dart        ← Dio + JWT interceptor
    └── secure_storage_service.dart
```

## Setup

1. Copy this folder into your monorepo as `mobile/` (or open it directly in Android Studio / VS Code).
2. Run:
   ```bash
   flutter pub get
   ```
3. Update the API base URL in `lib/services/api_service.dart`:
   ```dart
   static const String baseUrl = 'http://10.0.2.2:5298/api'; // Android emulator
   // iOS Simulator → http://localhost:5298/api
   // Physical device → http://<your-LAN-IP>:5298/api
   ```
4. Make sure the ASP.NET Core API is running and exposes:
   - `POST /api/auth/login`  → `{ accessToken, user: { id, email, fullName, role, tenantId, ... } }`
   - `POST /api/tenant/onboard` → same response shape after creating tenant + admin

5. Run:
   ```bash
   flutter run
   ```

## Auth flow

1. App starts → `initializeAuth()` reads token + user from secure storage.
2. If valid → show `DashboardScreen`.
3. Login / Register success → save token & user JSON → state becomes authenticated → UI switches automatically.
4. Logout / 401 → clear storage → back to `LoginScreen`.

## Dependencies

| Package                  | Purpose                          |
|--------------------------|----------------------------------|
| flutter_riverpod         | State management                 |
| dio                      | HTTP client                      |
| flutter_secure_storage   | Encrypted token storage          |
| go_router                | (ready for later routing)        |
