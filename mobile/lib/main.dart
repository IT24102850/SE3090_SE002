import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auth/app_role.dart';
import 'auth/app_notifications.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_repository.dart';
import 'auth/auth_session.dart';
import 'equipment_maintenance_screen.dart';
import 'inventory_dashboard.dart';
import 'purchase_order_approval_screen.dart';
import 'stock_check_screen.dart';
import 'stock_count_screen.dart';

const apiBaseUrl = String.fromEnvironment('API_BASE_URL',
    defaultValue: kIsWeb ? 'http://localhost:5107' : 'http://10.0.2.2:5107');
const navy = Color(0xFF12355B),
    mint = Color(0xFF0C8B7C),
    canvas = Color(0xFFF5F7FA),
    ink = Color(0xFF102A43);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthController(AuthRepository(apiBaseUrl: apiBaseUrl));
  runApp(App(auth: auth));
  auth.restore();
}

class App extends StatelessWidget {
  const App({super.key, required this.auth});
  final AuthController auth;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: auth,
      builder: (_, __) => MaterialApp(
          title: 'Stockwise',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: appMessengerKey,
          theme: appTheme(),
          home: auth.isRestoring
              ? const _BootScreen()
              : auth.session == null
                  ? LoginScreen(auth: auth)
                  : Shell(auth: auth, session: auth.session!)));
}

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
      seedColor: mint, brightness: Brightness.light, surface: Colors.white);
  OutlineInputBorder border(
          {Color color = const Color(0xFFD4DCE6), double width = 1}) =>
      OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width));
  return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(primary: mint, secondary: navy),
      scaffoldBackgroundColor: canvas,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: ink,
          elevation: 0,
          scrolledUnderElevation: 0),
      cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFE5EAF0)))),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: border(),
          enabledBorder: border(),
          focusedBorder: border(color: mint, width: 2),
          errorBorder: border(color: const Color(0xFFB42318)),
          focusedErrorBorder: border(color: const Color(0xFFB42318), width: 2)),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: mint,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: navy,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)))),
      navigationBarTheme: NavigationBarThemeData(
          height: 72,
          backgroundColor: Colors.white,
          indicatorColor: mint.withValues(alpha: .14),
          labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))));
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});
  final AuthController auth;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class Login extends LoginScreen {
  const Login({super.key, required super.auth});
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>(),
      _email = TextEditingController(),
      _password = TextEditingController();
  bool _obscure = true, _busy = false;
  String? _error;
  @override
  void dispose() {
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
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'We could not reach the service. Check your connection and try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 44, 24, 28),
                      children: [
                        const BrandLockup(),
                        const SizedBox(height: 42),
                        Text('Welcome back',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w900, color: ink)),
                        const SizedBox(height: 8),
                        const Text(
                            'Sign in to manage stock, counts, and approvals.',
                            style: TextStyle(
                                color: Color(0xFF60758A), fontSize: 16)),
                        const SizedBox(height: 28),
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Form(
                                    key: _form,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (_error != null)
                                            InlineError(message: _error!),
                                          if (_error != null)
                                            const SizedBox(height: 16),
                                          TextFormField(
                                              controller: _email,
                                              keyboardType:
                                                  TextInputType.emailAddress,
                                              textInputAction:
                                                  TextInputAction.next,
                                              decoration: const InputDecoration(
                                                  labelText: 'Email',
                                                  hintText: 'you@company.com',
                                                  prefixIcon: Icon(Icons
                                                      .alternate_email_rounded)),
                                              validator: (v) => v == null ||
                                                      !v.contains('@')
                                                  ? 'Enter a valid email address.'
                                                  : null),
                                          const SizedBox(height: 16),
                                          TextFormField(
                                              controller: _password,
                                              obscureText: _obscure,
                                              onFieldSubmitted: (_) => submit(),
                                              decoration: InputDecoration(
                                                  labelText: 'Password',
                                                  prefixIcon: const Icon(Icons
                                                      .lock_outline_rounded),
                                                  suffixIcon: IconButton(
                                                      onPressed: () => setState(
                                                          () => _obscure =
                                                              !_obscure),
                                                      tooltip: _obscure
                                                          ? 'Show password'
                                                          : 'Hide password',
                                                      icon: Icon(_obscure
                                                          ? Icons
                                                              .visibility_outlined
                                                          : Icons
                                                              .visibility_off_outlined))),
                                              validator: (v) =>
                                                  v == null || v.isEmpty
                                                      ? 'Enter your password.'
                                                      : null),
                                          const SizedBox(height: 24),
                                          FilledButton.icon(
                                              onPressed: _busy ? null : submit,
                                              icon: _busy
                                                  ? const SizedBox.square(
                                                      dimension: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  Colors.white))
                                                  : const Icon(Icons
                                                      .arrow_forward_rounded),
                                              label: Text(_busy
                                                  ? 'Signing in…'
                                                  : 'Sign in'))
                                        ])))),
                        const SizedBox(height: 22),
                        const Row(children: [
                          Icon(Icons.verified_user_outlined,
                              color: mint, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                              child: Text(
                                  'Your session is securely stored on this device.',
                                  style: TextStyle(color: Color(0xFF60758A))))
                        ])
                      ])))));
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.auth, required this.session});
  final AuthController auth;
  final AuthSession session;
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
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Sign out?'),
                content: const Text(
                    'You can sign in again whenever you need to continue work.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sign out'))
                ]));
    if (ok == true) {
      await widget.auth.logout();
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
          onOpenStockOperations: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StockCheckScreen(client: client)))),
      StockCountScreen(client: client),
      PurchaseOrderApprovalScreen(client: client, canApprove: canApprove),
      const EquipmentMaintenanceScreen(),
      const InsightsScreen()
    ];
    const destinations = [
      NavigationDestination(
          icon: Icon(Icons.space_dashboard_outlined),
          selectedIcon: Icon(Icons.space_dashboard_rounded),
          label: 'Home'),
      NavigationDestination(
          icon: Icon(Icons.qr_code_scanner_outlined),
          selectedIcon: Icon(Icons.qr_code_scanner_rounded),
          label: 'Count'),
      NavigationDestination(
          icon: Icon(Icons.assignment_turned_in_outlined),
          selectedIcon: Icon(Icons.assignment_turned_in_rounded),
          label: 'Orders'),
      NavigationDestination(
          icon: Icon(Icons.handyman_outlined),
          selectedIcon: Icon(Icons.handyman_rounded),
          label: 'Care'),
      NavigationDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights_rounded),
          label: 'Insights')
    ];
    return Scaffold(
        appBar: AppBar(
            toolbarHeight: 72,
            title: const BrandLockup(compact: true),
            actions: [
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
  Widget build(BuildContext context) => const Scaffold(
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
        BrandLockup(),
        SizedBox(height: 24),
        SizedBox.square(dimension: 24, child: CircularProgressIndicator())
      ])));
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
                    color: navy, borderRadius: BorderRadius.circular(14)),
                child:
                    const Icon(Icons.inventory_2_rounded, color: Colors.white)),
            const SizedBox(width: 12),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('STOCKWISE',
                      style: TextStyle(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 15 : 18,
                          color: ink)),
                  const Text('Inventory operations',
                      style: TextStyle(fontSize: 12, color: Color(0xFF60758A)))
                ])
          ]);
}

class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFFFFEDEE),
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFB42318)),
        const SizedBox(width: 8),
        Expanded(
            child:
                Text(message, style: const TextStyle(color: Color(0xFF8D1B14))))
      ]));
}

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('INSIGHTS',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3)),
            const SizedBox(height: 5),
            Text('Operational pulse',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900, color: ink)),
            const SizedBox(height: 8),
            const Text(
                'Use the dashboard for live inventory signals. Insights will expand as more historic movements are captured.',
                style: TextStyle(color: Color(0xFF60758A), height: 1.4)),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: mint.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.auto_graph_rounded,
                              color: mint)),
                      const SizedBox(height: 18),
                      const Text('Data-driven decisions',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: ink)),
                      const SizedBox(height: 8),
                      const Text(
                          'Refresh Home to review live stock value, low-stock items, and orders awaiting attention.',
                          style: TextStyle(
                              color: Color(0xFF60758A), height: 1.45)),
                    ]),
              ),
            ),
          ],
        ),
      );
}
