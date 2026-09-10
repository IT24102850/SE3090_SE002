import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/app_role.dart';
import 'auth/app_notifications.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_repository.dart';
import 'auth/auth_session.dart';
import 'analytics_screen.dart';
import 'equipment_maintenance_screen.dart';
import 'inventory_dashboard.dart';
import 'purchase_order_approval_screen.dart';
import 'stock_check_screen.dart';
import 'stock_count_screen.dart';

const apiBaseUrl = kIsWeb
    ? 'http://localhost:5298'
    : String.fromEnvironment('API_BASE_URL',
        defaultValue: 'http://10.0.2.2:5298');
const navy = Color(0xFF131B2E),
    mint = Color(0xFF10B981),
    canvas = Color(0xFF0B0F19),
    ink = Color(0xFFF8FAFC);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthController(AuthRepository(apiBaseUrl: apiBaseUrl));
  final themes = ThemeController();
  runApp(App(auth: auth, themes: themes));
  auth.restore();
  themes.restore();
}

class App extends StatelessWidget {
  const App({super.key, required this.auth, required this.themes});
  final AuthController auth;
  final ThemeController themes;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([auth, themes]),
      builder: (_, __) => MaterialApp(
          title: 'SME Inventory | Stock, Procurement & Analytics',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: appMessengerKey,
          theme: appTheme(themes.current),
          home: auth.isRestoring
              ? const _BootScreen()
              : auth.session == null
                  ? LoginScreen(auth: auth, themes: themes)
                  : Shell(auth: auth, session: auth.session!, themes: themes)));
}

enum AppThemeChoice { light, dark }

extension AppThemeChoiceDetails on AppThemeChoice {
  String get label => switch (this) {
        AppThemeChoice.light => 'Light mode',
        AppThemeChoice.dark => 'Dark mode',
      };

  IconData get icon => switch (this) {
        AppThemeChoice.light => Icons.light_mode_outlined,
        AppThemeChoice.dark => Icons.dark_mode_outlined,
      };
}

class ThemeController extends ChangeNotifier {
  static const _storageKey = 'sme_inventory.theme';
  AppThemeChoice current = AppThemeChoice.dark;

  Future<void> restore() async {
    try {
      final value =
          (await SharedPreferences.getInstance()).getString(_storageKey);
      current = AppThemeChoice.values
              .where((choice) => choice.name == value)
              .firstOrNull ??
          current;
    } catch (_) {
      // Theme persistence should never block access to the app.
    }
    notifyListeners();
  }

  Future<void> select(AppThemeChoice choice) async {
    if (choice == current) return;
    current = choice;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance())
          .setString(_storageKey, choice.name);
    } catch (_) {
      // Keep the selected theme for the current session if storage is unavailable.
    }
  }
}

ThemeData appTheme(AppThemeChoice choice) {
  final isDark = choice == AppThemeChoice.dark;
  const primary = Color(0xFF6366F1);
  const secondary = Color(0xFF06B6D4);
  final surface = isDark ? const Color(0xFF131B2E) : Colors.white;
  final surfaceRaised =
      isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
  final background = isDark ? canvas : const Color(0xFFF8FAFC);
  final onSurface = isDark ? ink : const Color(0xFF0F172A);
  final onSurfaceVariant =
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
  final outline = isDark ? const Color(0xFF232F48) : const Color(0xFFE2E8F0);
  final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: isDark ? Brightness.dark : Brightness.light,
      surface: surface);
  OutlineInputBorder border({Color? color, double width = 1}) =>
      OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color ?? outline, width: width));
  return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
          primary: primary,
          secondary: secondary,
          surface: surface,
          onSurface: onSurface,
          outline: outline,
          onSurfaceVariant: onSurfaceVariant),
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: onSurface,
          elevation: 0,
          scrolledUnderElevation: 0),
      cardTheme: CardThemeData(
          elevation: 0,
          color: surface,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: outline))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceRaised,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: border(),
          enabledBorder: border(),
          focusedBorder: border(color: primary, width: 2),
          errorBorder: border(color: const Color(0xFFEF4444)),
          focusedErrorBorder: border(color: const Color(0xFFEF4444), width: 2)),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: primary,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: primary,
              side: BorderSide(color: outline),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))),
      dialogTheme: DialogThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
              color: onSurface, fontSize: 20, fontWeight: FontWeight.w800),
          contentTextStyle: TextStyle(color: onSurfaceVariant)),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: surface,
          surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
      navigationBarTheme: NavigationBarThemeData(
          height: 72,
          backgroundColor: isDark ? const Color(0xFF0F1528) : Colors.white,
          indicatorColor: primary.withValues(alpha: .18),
          labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))));
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth, this.themes});
  final AuthController auth;
  final ThemeController? themes;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class Login extends LoginScreen {
  const Login({super.key, required super.auth, super.themes});
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _form = GlobalKey<FormState>(),
      _email = TextEditingController(),
      _password = TextEditingController();
  bool _obscure = true, _busy = false;
  String? _error;
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, .08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.login(_email.text.trim(), _password.text);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showAppNotification('You are signed in and ready to manage inventory.',
            tone: AppNotificationTone.success);
      });
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        showAppNotification(e.message, tone: AppNotificationTone.error);
      }
    } catch (error) {
      if (mounted) {
        final message =
            'Cannot reach the SME Inventory API at $apiBaseUrl. Start the backend and try again.';
        setState(() => _error = message);
        showAppNotification(message, tone: AppNotificationTone.error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                            position: _slideAnimation,
                            child: ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 32, 24, 28),
                                children: [
                                  Row(children: [
                                    const Expanded(child: BrandLockup()),
                                    if (widget.themes != null)
                                      ThemePicker(themes: widget.themes!)
                                  ]),
                                  const SizedBox(height: 26),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6366F1)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: const Color(0xFF6366F1)
                                              .withValues(alpha: 0.3)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.shield_outlined,
                                            size: 14, color: Color(0xFF818CF8)),
                                        SizedBox(width: 8),
                                        Text(
                                          'SME INVENTORY • SECURE MOBILE OPS',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.1,
                                            color: Color(0xFF818CF8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          const Color(0xFF6366F1)
                                              .withValues(alpha: .22),
                                          const Color(0xFF06B6D4)
                                              .withValues(alpha: .10),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: const Color(0xFF6366F1)
                                            .withValues(alpha: .30),
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(22),
                                            child: Image.network(
                                              'https://images.unsplash.com/photo-1556761175-b413da4baf72?auto=format&fit=crop&w=900&q=80',
                                              fit: BoxFit.cover,
                                              opacity:
                                                  const AlwaysStoppedAnimation(
                                                      .20),
                                              errorBuilder: (_, __, ___) =>
                                                  const SizedBox.shrink(),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(18),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 46,
                                                height: 46,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF6366F1)
                                                      .withValues(alpha: .20),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                child: const Icon(
                                                  Icons.inventory_2_rounded,
                                                  color: Color(0xFF818CF8),
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Your operations, in sync',
                                                      style: theme
                                                          .textTheme.titleMedium
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    const Text(
                                                      'Stock, procurement and analytics in one secure workspace.',
                                                      style: TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 12.5,
                                                        height: 1.35,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Welcome back',
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Sign in to continue managing your SME Inventory workspace.',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Card(
                                      child: Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Form(
                                              key: _form,
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Text(
                                                      'Secure sign in',
                                                      style: theme
                                                          .textTheme.titleMedium
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Use your organization account to access live data.',
                                                      style: TextStyle(
                                                        color: theme.colorScheme
                                                            .onSurfaceVariant,
                                                        fontSize: 12.5,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 18),
                                                    if (_error != null)
                                                      InlineError(
                                                          message: _error!),
                                                    if (_error != null)
                                                      const SizedBox(
                                                          height: 16),
                                                    TextFormField(
                                                        controller: _email,
                                                        keyboardType:
                                                            TextInputType
                                                                .emailAddress,
                                                        textInputAction:
                                                            TextInputAction
                                                                .next,
                                                        decoration: const InputDecoration(
                                                            labelText: 'Email',
                                                            hintText:
                                                                'you@company.com',
                                                            prefixIcon: Icon(Icons
                                                                .alternate_email_rounded)),
                                                        validator: (v) => v ==
                                                                    null ||
                                                                !v.contains('@')
                                                            ? 'Enter a valid email address.'
                                                            : null),
                                                    const SizedBox(height: 14),
                                                    TextFormField(
                                                        controller: _password,
                                                        obscureText: _obscure,
                                                        onFieldSubmitted: (_) =>
                                                            submit(),
                                                        decoration: InputDecoration(
                                                            labelText:
                                                                'Password',
                                                            prefixIcon:
                                                                const Icon(Icons
                                                                    .lock_outline_rounded),
                                                            suffixIcon: IconButton(
                                                                onPressed: () =>
                                                                    setState(() =>
                                                                        _obscure =
                                                                            !_obscure),
                                                                tooltip: _obscure
                                                                    ? 'Show password'
                                                                    : 'Hide password',
                                                                icon: Icon(_obscure
                                                                    ? Icons
                                                                        .visibility_outlined
                                                                    : Icons
                                                                        .visibility_off_outlined))),
                                                        validator: (v) => v ==
                                                                    null ||
                                                                v.isEmpty
                                                            ? 'Enter your password.'
                                                            : null),
                                                    const SizedBox(height: 20),
                                                    FilledButton.icon(
                                                        onPressed: _busy
                                                            ? null
                                                            : submit,
                                                        icon: _busy
                                                            ? const SizedBox
                                                                .square(
                                                                dimension: 18,
                                                                child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                    color: Colors
                                                                        .white))
                                                            : const Icon(Icons
                                                                .arrow_forward_rounded),
                                                        label: Text(_busy
                                                            ? 'Signing in…'
                                                            : 'Sign in')),
                                                  ])))),
                                  const SizedBox(height: 22),
                                  Row(children: [
                                    const Icon(Icons.verified_user_outlined,
                                        color: mint, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(
                                            'Protected access for your stock, procurement and analytics workspace.',
                                            style: TextStyle(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                                fontSize: 12.5)))
                                  ])
                                ])))))));
  }
}

class Shell extends StatefulWidget {
  const Shell(
      {super.key,
      required this.auth,
      required this.session,
      required this.themes});
  final AuthController auth;
  final AuthSession session;
  final ThemeController themes;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;
  late final client = widget.auth.authenticatedClient();
  @override
  void dispose() {
    client.close();
    super.dispose();
  }

  Future<void> confirmLogout() async {
    final ok = await showAppConfirmation(
        context: context,
        title: 'Sign out?',
        message: 'You can sign in again whenever you need to continue work.',
        confirmLabel: 'Sign out',
        icon: Icons.logout_rounded,
        accent: const Color(0xFFF87171));
    if (ok == true) {
      await widget.auth.logout();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showAppNotification('You have been signed out safely.',
            tone: AppNotificationTone.success);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canApprove =
        widget.session.hasAnyRole([AppRole.admin, AppRole.manager]) ||
            widget.session.roles.isEmpty;
    final pages = [
      InventoryDashboard(
          client: client,
          canApprove: canApprove,
          onOpenStockOperations: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StockCheckScreen(client: client)))),
      StockCountScreen(client: client),
      PurchaseOrderApprovalScreen(client: client, canApprove: canApprove),
      const EquipmentMaintenanceScreen(),
      InsightsScreen(client: client)
    ];
    const destinations = [
      NavigationDestination(
          icon: Icon(Icons.space_dashboard_outlined),
          selectedIcon: Icon(Icons.space_dashboard_rounded),
          label: 'Inventory'),
      NavigationDestination(
          icon: Icon(Icons.qr_code_scanner_outlined),
          selectedIcon: Icon(Icons.qr_code_scanner_rounded),
          label: 'Stock Log'),
      NavigationDestination(
          icon: Icon(Icons.assignment_turned_in_outlined),
          selectedIcon: Icon(Icons.assignment_turned_in_rounded),
          label: 'Purchase Orders'),
      NavigationDestination(
          icon: Icon(Icons.handyman_outlined),
          selectedIcon: Icon(Icons.handyman_rounded),
          label: 'Maintenance'),
      NavigationDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights_rounded),
          label: 'Analytics')
    ];
    return Scaffold(
        appBar: AppBar(
            toolbarHeight: 72,
            title: const BrandLockup(compact: true),
            actions: [
              // Role pill badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.session.roles.firstOrNull?.label ?? 'Staff',
                      style: const TextStyle(
                        color: Color(0xFF818CF8),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              ThemePicker(themes: widget.themes),
              IconButton(
                  onPressed: confirmLogout,
                  tooltip: 'Sign out',
                  icon: const Icon(Icons.logout_rounded))
            ]),
        body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(key: ValueKey(index), child: pages[index])),
        bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (v) => setState(() => index = v),
            destinations: destinations));
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLockup(),
            const SizedBox(height: 18),
            Text(
              'Preparing SME Inventory',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Container(
                width: compact ? 38 : 48,
                height: compact ? 38 : 48,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      Color(0xFF6366F1),
                      Color(0xFF8B5CF6),
                      Color(0xFFD946EF)
                    ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x336366F1),
                          blurRadius: 14,
                          offset: Offset(0, 6))
                    ]),
                child: const Icon(Icons.hub_rounded, color: Colors.white)),
            const SizedBox(width: 12),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('SME INVENTORY',
                      style: TextStyle(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 15 : 18,
                          color: Theme.of(context).colorScheme.onSurface)),
                  Text(
                      compact
                          ? 'Mobile Operations'
                          : 'POS • Inventory • Analytics',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant))
                ])
          ]);
}

class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key, required this.themes});
  final ThemeController themes;

  @override
  Widget build(BuildContext context) => PopupMenuButton<AppThemeChoice>(
        tooltip: 'Choose theme',
        icon: Icon(themes.current.icon),
        onSelected: themes.select,
        itemBuilder: (context) => AppThemeChoice.values
            .map((choice) => PopupMenuItem(
                  value: choice,
                  child: Row(children: [
                    Icon(choice.icon,
                        color: choice == themes.current
                            ? Theme.of(context).colorScheme.primary
                            : null),
                    const SizedBox(width: 12),
                    Expanded(child: Text(choice.label)),
                    if (choice == themes.current)
                      Icon(Icons.check_rounded,
                          color: Theme.of(context).colorScheme.primary),
                  ]),
                ))
            .toList(),
      );
}

class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0x33EF4444),
          border: Border.all(color: const Color(0x66EF4444)),
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFFCA5A5)),
        const SizedBox(width: 8),
        Expanded(
            child:
                Text(message, style: const TextStyle(color: Color(0xFFFECACA))))
      ]));
}
