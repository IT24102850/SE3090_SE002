import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'auth/app_role.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_repository.dart';
import 'auth/auth_session.dart';
import 'stock_count_screen.dart';
import 'stock_check_screen.dart';
import 'purchase_order_approval_screen.dart';
import 'equipment_maintenance_screen.dart';
import 'inventory_dashboard.dart';
import 'auth/app_notifications.dart';
import 'auth/notification_ws.dart';

// Chrome reaches the API through the host loopback address. Android emulators
// use 10.0.2.2 as their alias for the host machine's loopback address.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kIsWeb ? 'http://localhost:5107' : 'http://10.0.2.2:5107',
);
const navy = Color(0xFF173B5C),
    mint = Color(0xFF0E9F8A),
    canvas = Color(0xFFF4F7FB);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final auth = AuthController(AuthRepository(apiBaseUrl: apiBaseUrl));
  // initialize notifications websocket
  try {
    // ignore: unnecessary_statements
    () {
      // Lazy connect - NotificationService will attempt to reconnect on failure
      final ns = (NotificationService());
      ns.connect();
    }();
  } catch (_) {}
  runApp(App(auth: auth));
  auth.restore();
}

class App extends StatelessWidget {
  const App({super.key, required this.auth});
  final AuthController auth;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appMessengerKey,
      title: 'SME Inventory',
      theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: navy, brightness: Brightness.light),
          scaffoldBackgroundColor: canvas,
          dividerColor: const Color(0xFFE5EAF2),
          appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              surfaceTintColor: Colors.transparent),
          navigationBarTheme: NavigationBarThemeData(
              height: 74,
              backgroundColor: Colors.white,
              elevation: 1,
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              indicatorColor: navy.withValues(alpha: .12),
              indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
          cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white,
              surfaceTintColor: Colors.white,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Color(0xFFE4EAF2)))),
          inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
              border: border(),
              enabledBorder: border(),
              focusedBorder: border(navy, 2)),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: navy,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: navy,
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Color(0xFFCBD8E7)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
            ),
          ),
        ),
      home: AnimatedBuilder(
          animation: auth,
          builder: (_, __) => auth.isRestoring
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                          position: Tween<Offset>(
                                  begin: const Offset(0, .025), end: Offset.zero)
                              .animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic)),
                          child: child)),
                  child: auth.session == null
                      ? Login(key: const ValueKey('login'), auth: auth)
                      : Shell(
                          key: const ValueKey('shell'),
                          auth: auth,
                          session: auth.session!))),
    );
  }
}

OutlineInputBorder border(
        [Color color = const Color(0xFFE2E8F0), double width = 1]) =>
    OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width));

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});
  final AuthController auth;
  @override
  State<LoginScreen> createState() => _LoginState();
}

class Login extends LoginScreen {
  const Login({super.key, required super.auth});
}

class _LoginState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(), password = TextEditingController();
  final emailFocus = FocusNode(), passwordFocus = FocusNode();
  bool busy = false, hidden = true;
  String? error;
  Offset pointerGaze = Offset.zero;
  @override
  void initState() {
    super.initState();
    emailFocus.addListener(_refreshMascot);
    passwordFocus.addListener(_refreshMascot);
    email.addListener(_refreshMascot);
    emailFocus.onKeyEvent = (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshMascot();
      });
      return KeyEventResult.ignored;
    };
  }

  void _refreshMascot() => setState(() {});

  Offset get _owlGaze {
    if (!emailFocus.hasFocus) return pointerGaze;
    // Use a typical email-field width instead of the current text length.
    // Otherwise a caret at the end of even one typed character looks right.
    const trackedCharacters = 24;
    final caret = email.selection.baseOffset
        .clamp(0, trackedCharacters)
        .toDouble();
    final progress = caret / trackedCharacters;
    return Offset(-9 + (progress * 18), 5);
  }
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.login(email.text.trim(), password.text);
      showAppNotification('Signed in successfully.', tone: AppNotificationTone.success);
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
      showAppNotification(e.message, tone: AppNotificationTone.error);
    } catch (_) {
      const message = 'Unable to reach the server. Check the API connection and try again.';
      if (mounted) setState(() => error = message);
      showAppNotification(message, tone: AppNotificationTone.error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: Stack(children: [
        const Backdrop(),
        Center(
            child: MouseRegion(
                onHover: (event) {
                  if (emailFocus.hasFocus || passwordFocus.hasFocus) return;
                  final size = MediaQuery.sizeOf(context);
                  setState(() => pointerGaze = Offset(
                      ((event.position.dx - (size.width / 2)) / size.width *
                              18)
                          .clamp(-9, 9)
                          .toDouble(),
                      ((event.position.dy - (size.height * .22)) /
                                  size.height *
                              12)
                          .clamp(-5, 7)
                          .toDouble()));
                },
                child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                            offset: Offset(0, 24 * (1 - value)), child: child)),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                                side:
                                    const BorderSide(color: Color(0xFFE5EAF2))),
                            child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Form(
                                    key: form,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          SizedBox(
                                              height: 155,
                                              child: FittedBox(
                                                  fit: BoxFit.contain,
                                                  child: OwlMascot(
                                                      coverEyes: hidden &&
                                                          passwordFocus
                                                              .hasFocus,
                                                      sad: error != null,
                                                      content: error == null &&
                                                          !busy,
                                                      curious: emailFocus
                                                          .hasFocus,
                                                      gaze: _owlGaze))),
                                          const SizedBox(height: 4),
                                          const Logo(),
                                          const SizedBox(height: 28),
                                          Text('Welcome back',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800)),
                                          const SizedBox(height: 8),
                                          const Text(
                                              'Sign in to manage your inventory with ease.',
                                              style: TextStyle(
                                                  color: Color(0xFF667085))),
                                          const SizedBox(height: 28),
                                          TextFormField(
                                              controller: email,
                                              focusNode: emailFocus,
                                              keyboardType:
                                                  TextInputType.emailAddress,
                                              decoration: const InputDecoration(
                                                  labelText: 'Email address',
                                                  prefixIcon: Icon(Icons
                                                      .mail_outline_rounded)),
                                              validator: (v) =>
                                                  v == null || v.trim().isEmpty
                                                      ? 'Email is required'
                                                      : null),
                                          const SizedBox(height: 16),
                                          TextFormField(
                                              controller: password,
                                              focusNode: passwordFocus,
                                              obscureText: hidden,
                                              onFieldSubmitted: (_) => submit(),
                                              decoration: InputDecoration(
                                                  labelText: 'Password',
                                                  prefixIcon: const Icon(Icons
                                                      .lock_outline_rounded),
                                                  suffixIcon: IconButton(
                                                      onPressed: () => setState(
                                                          () =>
                                                              hidden = !hidden),
                                                      icon: Icon(hidden
                                                          ? Icons
                                                              .visibility_outlined
                                                          : Icons
                                                              .visibility_off_outlined))),
                                              validator: (v) =>
                                                  v == null || v.isEmpty
                                                      ? 'Password is required'
                                                      : null),
                                          if (error != null)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 16),
                                                child: ErrorBox(error!)),
                                          const SizedBox(height: 24),
                                          FilledButton.icon(
                                              onPressed: busy ? null : submit,
                                              icon: busy
                                                  ? const SizedBox(
                                                      height: 18,
                                                      width: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  Colors.white))
                                                  : const Icon(Icons
                                                      .arrow_forward_rounded),
                                              label: Text(busy
                                                  ? 'Signing in...'
                                                  : 'Sign in')),
                                          const SizedBox(height: 20),
                                          const Row(children: [
                                            Icon(Icons.shield_outlined,
                                                color: mint, size: 17),
                                            SizedBox(width: 8),
                                            Text(
                                                'Your session is secured and encrypted.',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF667085)))
                                          ])
                                        ])))))))))
      ]));
}

class Backdrop extends StatelessWidget {
  const Backdrop({super.key});
  @override
  Widget build(BuildContext c) => Stack(children: [
        Container(
            decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
              Color(0xFF07130F),
              Color(0xFF0B1D18),
              Color(0xFF050B09)
            ]))),
        Positioned(
            top: -150,
            left: -100,
            child: glow(420, const Color(0xFF2EE887).withValues(alpha: .12))),
        Positioned(
            bottom: -180,
            right: -90,
            child: glow(440, const Color(0xFF3B82F6).withValues(alpha: .12))),
      ]);
  Widget glow(double size, Color color) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}

class OwlMascot extends StatefulWidget {
  const OwlMascot({
    super.key,
    required this.coverEyes,
    required this.sad,
    required this.content,
    required this.curious,
    required this.gaze,
  });

  final bool coverEyes, sad, content, curious;
  final Offset gaze;

  @override
  State<OwlMascot> createState() => _OwlMascotState();
}

class _OwlMascotState extends State<OwlMascot> with TickerProviderStateMixin {
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  )..repeat(reverse: true);

  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );

  late final AnimationController _gazeEase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  Offset _displayGaze = Offset.zero;
  Offset _targetGaze = Offset.zero;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _targetGaze = widget.gaze;
    _scheduleBlink();
  }

  @override
  void didUpdateWidget(covariant OwlMascot old) {
    super.didUpdateWidget(old);
    if (old.gaze != widget.gaze) {
      _targetGaze = widget.gaze;
      _gazeEase.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _displayGaze = _targetGaze);
      });
    }
  }

  void _scheduleBlink() {
    final delay = Duration(milliseconds: 2200 + _rng.nextInt(3500));
    Future.delayed(delay, () async {
      if (!mounted) return;
      await _blink.forward();
      if (_rng.nextBool()) {
        await Future.delayed(const Duration(milliseconds: 90));
        if (mounted) await _blink.forward(from: 0.35);
      }
      if (mounted) await _blink.reverse();
      _scheduleBlink();
    });
  }

  @override
  void dispose() {
    _life.dispose();
    _blink.dispose();
    _gazeEase.dispose();
    super.dispose();
  }

  double get _mood {
    if (widget.sad) return -1;
    if (widget.content) return 0.75;
    return 0.15;
  }

  @override
  Widget build(BuildContext context) {
    final easedGaze = Offset.lerp(
          _displayGaze,
          _targetGaze,
          Curves.easeOutCubic.transform(_gazeEase.value),
        ) ??
        widget.gaze;

    return SizedBox(
      width: 280,
      height: 320,
      child: AnimatedBuilder(
        animation: Listenable.merge([_life, _blink]),
        builder: (_, __) {
          final t = _life.value;
          // Quick dip, slow rise — characteristic owl nod
          final nodPhase = math.sin(t * math.pi * 2);
          final nod = nodPhase > 0
              ? nodPhase * 0.055
              : nodPhase * 0.028;
          final bobY = math.sin(t * math.pi * 2 + 0.4) * 2.8;
          final sway = math.sin(t * math.pi * 2 * 0.45) * 0.018;
          final breathe = 1 + math.sin(t * math.pi * 2) * 0.012;

          final headTurn = easedGaze.dx / 68 +
              (widget.curious ? 0.06 : 0) +
              sway * 0.4;
          final headTilt = easedGaze.dy / 820 +
              sway +
              (widget.curious ? -0.04 : 0);

          return Transform.translate(
            offset: Offset(0, bobY),
            child: Transform.scale(
              scale: breathe,
              alignment: const Alignment(0, 0.35),
              child: Transform(
                alignment: const Alignment(0, -0.12),
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0016)
                  ..rotateX(nod + (widget.curious ? -0.025 : 0))
                  ..rotateY(headTurn)
                  ..rotateZ(headTilt),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      size: const Size(280, 320),
                      painter: _RealisticOwlPainter(
                        sad: widget.sad,
                        mood: _mood,
                        tuftSway: sway,
                      ),
                    ),
                    Positioned(
                      top: 76,
                      left: 56,
                      child: _RealisticEye(
                        gaze: easedGaze,
                        sad: widget.sad,
                        mood: _mood,
                        blink: _blink.value,
                      ),
                    ),
                    Positioned(
                      top: 76,
                      right: 56,
                      child: _RealisticEye(
                        gaze: easedGaze,
                        sad: widget.sad,
                        mood: _mood,
                        blink: _blink.value,
                        flipHighlight: true,
                      ),
                    ),
                    Positioned(
                      top: 180,
                      child: OwlExpression(sad: widget.sad, mood: _mood),
                    ),
                    Positioned(
                      top: 30,
                      left: 10,
                      right: 10,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutBack,
                        offset: widget.coverEyes
                            ? Offset.zero
                            : const Offset(0, 1.2),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          opacity: widget.coverEyes ? 1 : 0,
                          child: CustomPaint(
                            size: const Size(260, 160),
                            painter: _OwlWingCoversPainter(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class OwlExpression extends StatelessWidget {
  const OwlExpression({super.key, required this.sad, required this.mood});
  final bool sad;
  final double mood;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: sad ? -1.0 : mood),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (_, value, __) => CustomPaint(
          size: const Size(92, 38),
          painter: _OwlExpressionPainter(value),
        ),
      );
}

class _OwlExpressionPainter extends CustomPainter {
  const _OwlExpressionPainter(this.mood);
  final double mood;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = Paint()
      ..color = const Color(0xFF241006)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    if (mood > 0.3) {
      // Content owl: subtle relaxed beak parting + soft upturn
      final smile = Path()
        ..moveTo(24, 18 - mood * 2)
        ..quadraticBezierTo(46, 28 + mood * 4, 68, 18 - mood * 2);
      canvas.drawPath(smile, dark);
      final lower = Path()
        ..moveTo(38, 24 + mood * 2)
        ..quadraticBezierTo(46, 30 + mood * 3, 54, 24 + mood * 2);
      canvas.drawPath(
        lower,
        dark
          ..strokeWidth = 2.2
          ..color = const Color(0xFF3A1707).withValues(alpha: .7),
      );
    } else if (mood < 0) {
      final frown = Path()..moveTo(28, 20 - mood * 5);
      frown.quadraticBezierTo(46, 34 + mood * 28, 64, 20 - mood * 5);
      canvas.drawPath(frown, dark);
      final brow = Paint()
        ..color = const Color(0xFF3A1707)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      final d = -mood;
      canvas.drawLine(
          const Offset(8, 7), Offset(30, 12 + d * 4), brow);
      canvas.drawLine(
          const Offset(84, 7), Offset(62, 12 + d * 4), brow);
    } else {
      final neutral = Path()
        ..moveTo(32, 22)
        ..quadraticBezierTo(46, 26, 60, 22);
      canvas.drawPath(neutral, dark);
    }
  }

  @override
  bool shouldRepaint(covariant _OwlExpressionPainter old) =>
      old.mood != mood;
}

class _RealisticEye extends StatelessWidget {
  const _RealisticEye({
    required this.gaze,
    required this.sad,
    required this.mood,
    required this.blink,
    this.flipHighlight = false,
  });

  final Offset gaze;
  final bool sad;
  final double mood, blink;
  final bool flipHighlight;

  @override
  Widget build(BuildContext context) => Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .55),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: CustomPaint(
          painter: _RealisticEyePainter(
            gaze,
            sad,
            mood,
            blink,
            flipHighlight,
          ),
        ),
      );
}

class _RealisticEyePainter extends CustomPainter {
  const _RealisticEyePainter(
    this.gaze,
    this.sad,
    this.mood,
    this.blink,
    this.flipHighlight,
  );

  final Offset gaze;
  final bool sad;
  final double mood, blink;
  final bool flipHighlight;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFF151210),
    );

    final irisRadius = radius - 4;
    final colors = sad
        ? [
            const Color(0xFFD97706),
            const Color(0xFF78350F),
            Colors.black,
          ]
        : [
            const Color(0xFFFBBF24),
            const Color(0xFFD97706),
            const Color(0xFF451A03),
          ];

    canvas.drawCircle(
      center,
      irisRadius,
      Paint()
        ..shader = RadialGradient(
          colors: colors,
          stops: const [.2, .75, 1],
        ).createShader(Rect.fromCircle(center: center, radius: irisRadius)),
    );

    final detail = Paint()
      ..color = Colors.black.withValues(alpha: .22)
      ..strokeWidth = 1;
    for (var i = 0; i < 24; i++) {
      final angle = i * 15 * math.pi / 180;
      canvas.drawLine(
        Offset(
          center.dx + irisRadius * .42 * math.cos(angle),
          center.dy + irisRadius * .42 * math.sin(angle),
        ),
        Offset(
          center.dx + irisRadius * math.cos(angle),
          center.dy + irisRadius * math.sin(angle),
        ),
        detail,
      );
    }

    final pupilScale = sad ? 0.82 : (0.92 + mood * 0.08);
    final pupil = Offset(
      center.dx + gaze.dx * .62,
      center.dy + gaze.dy * .62,
    );
    final pupilR = (sad ? 13.0 : 16.0) * pupilScale;
    canvas.drawCircle(
      pupil,
      pupilR,
      Paint()..color = const Color(0xFF030303),
    );

    final hx = flipHighlight ? 5.0 : -5.0;
    canvas.drawCircle(
      Offset(pupil.dx + hx, pupil.dy - 6),
      4.5,
      Paint()..color = Colors.white.withValues(alpha: .9),
    );
    canvas.drawCircle(
      Offset(pupil.dx - hx * .6, pupil.dy + 6),
      2,
      Paint()..color = Colors.white.withValues(alpha: .55),
    );

    // Content squint — relaxed half-lids when happy
    final squint = mood > 0.4 ? (mood - 0.4) * 1.4 : 0.0;
    final lidClose = blink.clamp(0.0, 1.0) + squint * 0.35;
    if (lidClose > 0.01) {
      final lid = Paint()
        ..color = const Color(0xFF8A4B1B)
        ..style = PaintingStyle.fill;
      final lidPath = Path()
        ..moveTo(2, 2)
        ..quadraticBezierTo(
          center.dx,
          center.dy - radius + lidClose * radius * 1.85,
          size.width - 2,
          2,
        )
        ..lineTo(size.width - 2, center.dy)
        ..quadraticBezierTo(center.dx, center.dy - 4, 2, center.dy)
        ..close();
      canvas.drawPath(lidPath, lid);

      final lash = Paint()
        ..color = const Color(0xFF271004)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 1),
        math.pi * 1.05,
        math.pi * 0.9,
        false,
        lash,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RealisticEyePainter old) =>
      old.gaze != gaze ||
      old.sad != sad ||
      old.mood != mood ||
      old.blink != blink;
}

class _RealisticOwlPainter extends CustomPainter {
  const _RealisticOwlPainter({
    required this.sad,
    required this.mood,
    required this.tuftSway,
  });

  final bool sad;
  final double mood, tuftSway;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final body = Path()
      ..moveTo(w * .15, h * .05)
      ..quadraticBezierTo(w * .3, h * .12, w * .35, h * .15)
      ..quadraticBezierTo(w * .5, h * .12, w * .65, h * .15)
      ..quadraticBezierTo(w * .7, h * .12, w * .85, h * .05)
      ..cubicTo(w * .96, h * .38, w * .9, h * .82, w * .5, h * .9)
      ..cubicTo(w * .1, h * .82, w * .04, h * .38, w * .15, h * .05);

    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.black.withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.2),
          colors: const [
            Color(0xFF8A4B1B),
            Color(0xFF451A03),
            Color(0xFF1C0A00),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Ear tufts
    final tuft = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF6B3A12), Color(0xFF271004)],
      ).createShader(Rect.fromLTWH(0, 0, w, h * .3));
    for (final side in [-1.0, 1.0]) {
      final tx = w * .5 + side * w * .22 + tuftSway * side * 30;
      final tuftPath = Path()
        ..moveTo(tx - side * 8, h * .08)
        ..quadraticBezierTo(
          tx + side * 18,
          h * .01 + tuftSway * 20,
          tx + side * 6,
          h * .22,
        )
        ..quadraticBezierTo(tx, h * .18, tx - side * 8, h * .08);
      canvas.drawPath(tuftPath, tuft);
    }

    final disk = Path()
      ..moveTo(w * .5, h * .22)
      ..cubicTo(w * .35, h * .15, w * .18, h * .25, w * .18, h * .47)
      ..cubicTo(w * .18, h * .68, w * .38, h * .76, w * .5, h * .71)
      ..cubicTo(w * .62, h * .76, w * .82, h * .68, w * .82, h * .47)
      ..cubicTo(w * .82, h * .25, w * .65, h * .15, w * .5, h * .22);

    canvas.drawPath(
      disk,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFF3D6), Color(0xFFD97706), Color(0xFF78350F)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      disk,
      Paint()
        ..color = const Color(0xFF271004)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    final feather = Paint()
      ..color = const Color(0xFF271004).withValues(alpha: .32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var y = h * .42; y < h * .72; y += 12) {
      for (var x = w * .28; x < w * .72; x += 16) {
        canvas.drawArc(
          Rect.fromLTWH(x, y, 10, 6),
          0,
          math.pi,
          false,
          feather,
        );
      }
    }

    final beak = Path()
      ..moveTo(w * .5, h * .43)
      ..quadraticBezierTo(w * .55, h * .49, w * .5, h * .6)
      ..quadraticBezierTo(w * .45, h * .49, w * .5, h * .43);
    canvas.drawPath(
      beak,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: sad
              ? const [Color(0xFF64748B), Color(0xFF0F172A)]
              : const [
                  Color(0xFFF59E0B),
                  Color(0xFFB45309),
                  Color(0xFF451A03),
                ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  @override
  bool shouldRepaint(covariant _RealisticOwlPainter old) =>
      old.sad != sad || old.mood != mood || old.tuftSway != tuftSway;
}

class _OwlWingCoversPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF451A03), Color(0xFF8A4B1B), Color(0xFF271004)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    final left = Path()
      ..moveTo(0, h * .2)
      ..cubicTo(w * .2, 0, w * .45, h * .3, w * .48, h)
      ..cubicTo(w * .3, h * .9, w * .1, h * .6, 0, h * .2);
    final right = Path()
      ..moveTo(w, h * .2)
      ..cubicTo(w * .8, 0, w * .55, h * .3, w * .52, h)
      ..cubicTo(w * .7, h * .9, w * .9, h * .6, w, h * .2);
    canvas
      ..drawPath(left, paint)
      ..drawPath(right, paint);
  }

  @override
  bool shouldRepaint(covariant _OwlWingCoversPainter old) => false;
}

class CursorCat extends StatefulWidget {
  const CursorCat({super.key});
  @override
  State<CursorCat> createState() => _CursorCatState();
}

class _CursorCatState extends State<CursorCat> {
  Offset pointer = Offset.zero;
  @override
  Widget build(BuildContext c) => MouseRegion(
      onHover: (event) => setState(() => pointer = event.localPosition),
      child: SizedBox(
          width: 250,
          height: 330,
          child: LayoutBuilder(builder: (_, box) {
            final dx = (((pointer.dx - box.maxWidth / 2) / box.maxWidth)
                        .clamp(-1.0, 1.0) *
                    7)
                .toDouble();
            final dy = (((pointer.dy - box.maxHeight / 2) / box.maxHeight)
                        .clamp(-1.0, 1.0) *
                    5)
                .toDouble();
            return Stack(alignment: Alignment.center, children: [
              Positioned(
                  bottom: 28,
                  child: Container(
                      width: 190,
                      height: 185,
                      decoration: BoxDecoration(
                          color: const Color(0xFFF2B86D),
                          borderRadius: BorderRadius.circular(92),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFFFFD07B)
                                    .withValues(alpha: .24),
                                blurRadius: 40)
                          ]))),
              const Positioned(top: 36, left: 47, child: _CatEar(flip: false)),
              const Positioned(top: 36, right: 47, child: _CatEar(flip: true)),
              Positioned(
                  top: 104,
                  child: Row(children: [
                    _CatEye(dx: dx, dy: dy),
                    const SizedBox(width: 28),
                    _CatEye(dx: dx, dy: dy)
                  ])),
              const Positioned(
                  top: 171,
                  child: Icon(Icons.favorite_rounded,
                      size: 16, color: Color(0xFF9E3D39))),
              const Positioned(
                  top: 198,
                  child: Icon(Icons.sentiment_satisfied_alt_rounded,
                      size: 38, color: Color(0xFF55352B))),
              Positioned(
                  bottom: 0,
                  child: Container(
                      width: 130,
                      height: 12,
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .25),
                          borderRadius: BorderRadius.circular(30)))),
            ]);
          })));
}

class _CatEar extends StatelessWidget {
  const _CatEar({required this.flip});
  final bool flip;
  @override
  Widget build(BuildContext c) => Transform.flip(
      flipX: flip,
      child: CustomPaint(size: const Size(75, 82), painter: _EarPainter()));
}

class _EarPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Path()
      ..moveTo(0, s.height)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height)
      ..close();
    c.drawPath(p, Paint()..color = const Color(0xFFF2B86D));
    final inner = Path()
      ..moveTo(18, s.height - 8)
      ..lineTo(s.width - 13, 18)
      ..lineTo(s.width - 12, s.height - 8)
      ..close();
    c.drawPath(inner, Paint()..color = const Color(0xFFD97E7A));
  }

  @override
  bool shouldRepaint(CustomPainter old) => false;
}

class _CatEye extends StatelessWidget {
  const _CatEye({required this.dx, required this.dy});
  final double dx, dy;
  @override
  Widget build(BuildContext c) => Container(
      width: 48,
      height: 55,
      decoration:
          const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: Transform.translate(
          offset: Offset(dx, dy),
          child: const Center(
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: Color(0xFF18322A), shape: BoxShape.circle),
                  child: SizedBox(width: 18, height: 18)))));
}

class LampScene extends StatefulWidget {
  const LampScene({super.key});
  @override
  State<LampScene> createState() => _LampSceneState();
}

class _LampSceneState extends State<LampScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat(reverse: true);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final glow = 32 + (controller.value * 18);
          return SizedBox(
              width: 250,
              height: 390,
              child: Stack(alignment: Alignment.center, children: [
                Positioned(
                    bottom: 28,
                    child: Container(
                        width: 215,
                        height: 250,
                        decoration: BoxDecoration(
                            gradient: RadialGradient(colors: [
                              const Color(0xFFCCFF8E).withValues(alpha: .24),
                              Colors.transparent
                            ]),
                            borderRadius: BorderRadius.circular(150)))),
                Positioned(
                    top: 55,
                    child: Container(
                        width: 145,
                        height: 102,
                        decoration: BoxDecoration(
                            color: const Color(0xFF8BB68E),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(70),
                                bottom: Radius.circular(20)),
                            boxShadow: [
                              BoxShadow(
                                  color: const Color(0xFFBBFF77)
                                      .withValues(alpha: .45),
                                  blurRadius: glow,
                                  spreadRadius: 3)
                            ]))),
                Positioned(
                    top: 145,
                    child: Container(
                        width: 132,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: Color(0xFFF5F0BF),
                            borderRadius:
                                BorderRadius.all(Radius.circular(40))))),
                Positioned(
                    top: 150,
                    child: Container(
                        width: 5, height: 150, color: const Color(0xFFD5D9D2))),
                Positioned(
                    top: 264,
                    left: 141,
                    child: Container(
                        width: 3, height: 52, color: const Color(0xFFD5D9D2))),
                Positioned(
                    top: 315,
                    child: Container(
                        width: 88,
                        height: 13,
                        decoration: BoxDecoration(
                            color: const Color(0xFFD5D9D2),
                            borderRadius: BorderRadius.circular(100),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: .35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 5))
                            ]))),
              ]));
        },
      );
}

class Logo extends StatelessWidget {
  const Logo({super.key});
  @override
  Widget build(BuildContext c) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: navy, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.inventory_2_rounded, color: Colors.white)),
        const SizedBox(width: 12),
        const Flexible(
            child: Text('SME Inventory',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)))
      ]);
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext c) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF1F0),
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Color(0xFFB42318)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Text(message, style: const TextStyle(color: Color(0xFFB42318))))
      ]));
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
  late final stockClient = widget.auth.authenticatedClient();

  @override
  void dispose() {
    stockClient.close();
    super.dispose();
  }

  Future<void> confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF7C3AED)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.logout_rounded, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text('Ready to sign out?', style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Your work is saved. You can sign back in whenever you are ready.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF667085), height: 1.4)),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Stay signed in'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sign out'))),
            ]),
          ]),
        ),
      ),
    );
    if (shouldLogout == true) {
      await widget.auth.logout();
      showAppNotification('You have been safely signed out. See you next time!', tone: AppNotificationTone.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final analytics =
        widget.session.hasAnyRole([AppRole.admin, AppRole.manager]);
    final pages = [
      InventoryDashboard(
        client: stockClient,
        onOpenStockOperations: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StockCheckScreen(client: stockClient),
          ),
        ),
      ),
      StockCountScreen(client: stockClient),
      PurchaseOrderApprovalScreen(
          client: stockClient,
          canApprove: widget.session.hasAnyRole([AppRole.admin, AppRole.manager])),
      const EquipmentMaintenanceScreen(),
      if (analytics) const Analytics(),
    ];
    final destinations = [
      const NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: 'Inventory'),
      const NavigationDestination(
          icon: Icon(Icons.fact_check_outlined),
          selectedIcon: Icon(Icons.fact_check),
          label: 'Stock count'),
      const NavigationDestination(
          icon: Icon(Icons.approval_outlined),
          selectedIcon: Icon(Icons.approval),
          label: 'Approvals'),
      const NavigationDestination(
          icon: Icon(Icons.build_outlined),
          selectedIcon: Icon(Icons.build),
          label: 'Maintenance'),
      if (analytics)
        const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Analytics')
    ];
    final current = index >= pages.length ? 0 : index;
    return Scaffold(
        appBar: AppBar(
            toolbarHeight: 78,
            backgroundColor: navy,
            foregroundColor: Colors.white,
            flexibleSpace: const DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF173B5C), Color(0xFF0E6972)]))),
            title: const Logo(), actions: [
          Padding(
              padding: const EdgeInsets.only(right: 16),
              child: IconButton.filledTonal(
                  onPressed: confirmLogout,
                  tooltip: 'Sign out',
                  icon: const Icon(Icons.logout_rounded)))
        ]),
        body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: KeyedSubtree(key: ValueKey(current), child: pages[current])),
        bottomNavigationBar: NavigationBar(
            selectedIndex: current,
            onDestinationSelected: (v) => setState(() => index = v),
            destinations: destinations));
  }
}

class Inventory extends StatelessWidget {
  const Inventory({super.key});
  @override
  Widget build(BuildContext c) => PageFrame(
          title: 'Inventory at a glance',
          subtitle:
              'A clear view of stock health and what needs attention today.',
          action: FilledButton.icon(
              onPressed: () => showAppNotification(
                  'Add item is not available in the mobile app yet.'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add item')),
          children: [
            LayoutBuilder(builder: (_, b) {
              final count = b.maxWidth > 900
                  ? 4
                  : b.maxWidth > 600
                      ? 2
                      : 1;
              return GridView.count(
                  crossAxisCount: count,
                  childAspectRatio: count == 1 ? 2.5 : 1.55,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: const [
                    Metric('Total items', '248', '12 added this month',
                        Icons.inventory_2_outlined, navy),
                    Metric('In stock', '1,842', 'Units available',
                        Icons.check_circle_outline, mint),
                    Metric('Low stock', '18', 'Needs attention',
                        Icons.warning_amber_rounded, Color(0xFFD97706)),
                    Metric('Suppliers', '24', 'Active partners',
                        Icons.local_shipping_outlined, Color(0xFF7C3AED))
                  ]);
            }),
            const SizedBox(height: 28),
            const Heading(
                'Quick actions', 'Keep your daily stock work moving.'),
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 12, children: const [
              ActionTile(Icons.add_box_outlined, 'New item', navy),
              ActionTile(Icons.swap_horiz_rounded, 'Stock adjustment', mint),
              ActionTile(Icons.shopping_cart_outlined, 'Purchase order',
                  Color(0xFF7C3AED)),
              ActionTile(Icons.group_outlined, 'Suppliers', Color(0xFFD97706))
            ]),
            const SizedBox(height: 28),
            const Heading(
                'Stock alerts', 'Items that may need reordering soon.'),
            const SizedBox(height: 14),
            const Alerts()
          ]);
}

class Analytics extends StatelessWidget {
  const Analytics({super.key});
  @override
  Widget build(BuildContext c) => PageFrame(
          title: 'Inventory intelligence',
          subtitle: 'Use these signals to make confident stocking decisions.',
          action: OutlinedButton.icon(
              onPressed: () => showAppNotification(
                  'Report export is not available in the mobile app yet.'),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export report')),
          children: const [
            Wrap(spacing: 16, runSpacing: 16, children: [
              Metric('Stock turnover', '6.8x', '+8.2% vs last month',
                  Icons.trending_up_rounded, mint),
              Metric('Inventory value', 'LKR 42.8k', 'Across 248 products',
                  Icons.savings_outlined, navy),
              Metric('Days of stock', '31', 'Healthy coverage',
                  Icons.timer_outlined, Color(0xFF7C3AED))
            ]),
            SizedBox(height: 28),
            ChartCard()
          ]);
}

class PageFrame extends StatelessWidget {
  const PageFrame(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.action,
      required this.children});
  final String title, subtitle;
  final Widget action;
  final List<Widget> children;
  @override
  Widget build(BuildContext c) => LayoutBuilder(
      builder: (_, b) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              b.maxWidth > 700 ? 40 : 20, 12, b.maxWidth > 700 ? 40 : 20, 36),
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                            spacing: 20,
                            runSpacing: 14,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('OPERATIONS',
                                        style: TextStyle(
                                            color: mint,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.2)),
                                    const SizedBox(height: 6),
                                    Text(title,
                                        style: Theme.of(c)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 6),
                                    Text(subtitle,
                                        style: const TextStyle(
                                            color: Color(0xFF667085)))
                                  ]),
                              action
                            ]),
                        const SizedBox(height: 28),
                        ...children
                      ])))));
}

class Metric extends StatelessWidget {
  const Metric(this.label, this.value, this.note, this.icon, this.color,
      {super.key});
  final String label, value, note;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext c) => Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE7ECF3))),
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: color)),
            const Spacer(),
            Text(value,
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(note,
                style: const TextStyle(fontSize: 12, color: Color(0xFF667085)))
          ])));
}

class Heading extends StatelessWidget {
  const Heading(this.title, this.detail, {super.key});
  final String title, detail;
  @override
  Widget build(BuildContext c) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: Theme.of(c)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        Text(detail, style: const TextStyle(color: Color(0xFF667085)))
      ]);
}

class ActionTile extends StatelessWidget {
  const ActionTile(this.icon, this.label, this.color, {super.key});
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext c) => LayoutBuilder(builder: (_, constraints) {
        final width = constraints.maxWidth < 190 ? constraints.maxWidth : 190.0;
        return InkWell(
            onTap: () => showAppNotification('$label is not available yet.'),
            borderRadius: BorderRadius.circular(16),
            child: Ink(
                width: width,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x080F172A),
                          blurRadius: 12,
                          offset: Offset(0, 4))
                    ]),
                child: Row(children: [
                  Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: .11),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: color, size: 21)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)))
                ])));
      });
}

class Alerts extends StatelessWidget {
  const Alerts({super.key});
  @override
  Widget build(BuildContext c) => Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE7ECF3))),
      child: const Column(children: [
        Alert('Premium Coffee Beans', 'SKU-00132', '6 units left',
            Color(0xFFD97706)),
        Divider(height: 1),
        Alert('Packaging Boxes - Medium', 'SKU-00598', '11 units left',
            Color(0xFFD97706)),
        Divider(height: 1),
        Alert('Vanilla Syrup', 'SKU-00324', 'Out of stock', Color(0xFFDC2626))
      ]));
}

class Alert extends StatelessWidget {
  const Alert(this.item, this.sku, this.status, this.color, {super.key});
  final String item, sku, status;
  final Color color;
  @override
  Widget build(BuildContext c) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.inventory_2_outlined, color: color)),
      title: Text(item, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sku),
      trailing: Text(status,
          style: TextStyle(color: color, fontWeight: FontWeight.w700)));
}

class ChartCard extends StatelessWidget {
  const ChartCard({super.key});
  @override
  Widget build(BuildContext c) => Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE7ECF3))),
      child: const Padding(
          padding: EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Stock movement',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 5),
            Text('Incoming and outgoing stock over the last 6 months',
                style: TextStyle(color: Color(0xFF667085))),
            SizedBox(height: 30),
            Icon(Icons.show_chart_rounded, color: mint, size: 80),
            SizedBox(height: 15),
            Text(
                'Detailed reporting will appear here as inventory data is connected.',
                style: TextStyle(color: Color(0xFF667085)))
          ])));
}
