import 'dart:math' as math;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/alerts_controller.dart';
import '../router/route_names.dart';
import '../services/notifications_service.dart';
import '../services/prefs.dart';

/// First-run onboarding wizard. Bump [version] when the content changes to
/// re-show it to existing users.
class IntroWizardScreen extends StatefulWidget {
  const IntroWizardScreen({super.key});

  static const int version = 3;
  static const String _key = 'onboarding.version';

  /// Whether the wizard should be shown (not yet completed for this version).
  static bool shouldShow() => Prefs.getInt(_key, 0) < version;

  static void markCompleted() => Prefs.setInt(_key, version);

  @override
  State<IntroWizardScreen> createState() => _IntroWizardScreenState();
}

class _IntroWizardScreenState extends State<IntroWizardScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _notificationsEnabled = false;
  bool _requestingNotifications = false;

  @override
  void initState() {
    super.initState();
    NotificationsService.instance.notificationsEnabled().then((enabled) {
      if (mounted) setState(() => _notificationsEnabled = enabled);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Widget> get _pages => [
    _Page(
      icon: Icons.traffic,
      title: 'Dobrodošli v Prometniku',
      body:
          'Dogodki, kamere, vreme in stanje cest ter potovalni časi na '
          'slovenskih cestah — na enem mestu.',
    ),
    _Page(
      icon: Icons.map,
      title: 'Karta in kamere',
      body:
          'Na karti so vremenske postaje, kamere in dogodki. Zavihek Kamere '
          'zbira kamere vremenskih postaj in kamere DARS s sliko v živo.',
    ),
    _Page(
      icon: Icons.warning_amber_rounded,
      title: 'Dogodki in časi',
      body:
          'Zapore, zastoji in dela s prizadetim odsekom na karti. Filtriraj '
          'jih po vrsti. Zavihek Časi prikaže potovalne čase na glavnih '
          'poteh.',
    ),
    _Page(
      icon: Icons.near_me,
      title: 'Opozorila v bližini',
      body:
          'V zavihku Bližina vklopi lokacijo za dogodke v bližini. Za '
          'spremljane ceste tapni "Izberi na karti" in nato tapni cesto na '
          'karti — obvestili te bomo o dogodkih na njej.',
      child: Consumer(
        builder: (context, ref, _) {
          final alerts = ref.watch(alertsProvider);
          final problem = alerts.locationProblemMessage;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (problem != null) ...[
                Text(
                  problem,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (problem != null && alerts.canOpenLocationSettings)
                AdaptiveButton(
                  onPressed: () =>
                      ref.read(alertsProvider.notifier).openLocationSettings(),
                  label: 'Odpri nastavitve',
                  style: AdaptiveButtonStyle.tinted,
                )
              else
                AdaptiveButton(
                  onPressed: alerts.locationEnabled || alerts.requesting
                      ? () {}
                      : () =>
                            ref.read(alertsProvider.notifier).enableLocation(),
                  label: alerts.locationEnabled
                      ? 'Lokacija vklopljena'
                      : (alerts.requesting
                            ? 'Pridobivanje…'
                            : 'Vklopi lokacijo'),
                  style: AdaptiveButtonStyle.tinted,
                ),
            ],
          );
        },
      ),
    ),
    _Page(
      icon: Icons.notifications_active_outlined,
      title: 'Obvestila',
      body:
          'Za spremljane ceste in potovalne čase lahko Prometnik pošlje '
          'obvestilo, ko se pojavijo dogodki ali ko se potovalni čas izboljša '
          'oziroma poslabša.',
      child: AdaptiveButton(
        onPressed: _notificationsEnabled || _requestingNotifications
            ? () {}
            : _enableNotifications,
        label: _notificationsEnabled
            ? 'Obvestila vklopljena'
            : (_requestingNotifications ? 'Pridobivanje…' : 'Vklopi obvestila'),
        style: AdaptiveButtonStyle.tinted,
      ),
    ),
    _Page(
      icon: Icons.verified_outlined,
      title: 'Viri podatkov',
      body:
          'Promet, kamere in potovalni časi: DARS / promet.si. Vreme in '
          'stanje cest: ceste.si, DRSI CVIS in ARSO. Karta: © OpenStreetMap '
          '(ODbL) in Seznam (mapy.com). Podatki so informativne narave.',
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() {
    IntroWizardScreen.markCompleted();
    if (mounted) context.go(AppRoutes.map);
  }

  Future<void> _enableNotifications() async {
    if (_requestingNotifications || _notificationsEnabled) return;
    setState(() => _requestingNotifications = true);
    var enabled = false;
    try {
      enabled = await NotificationsService.instance.requestPermission();
    } on Exception catch (e) {
      debugPrint('notification permission failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _notificationsEnabled = enabled;
          _requestingNotifications = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pages = _pages;
    final isLast = _page == pages.length - 1;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Preskoči'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: pages,
              ),
            ),
            // Dots.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: AdaptiveButton(
                onPressed: _next,
                label: isLast ? 'Začni' : 'Naprej',
                size: AdaptiveButtonSize.large,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? child;

  const _Page({
    required this.icon,
    required this.title,
    required this.body,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Scrolls when large text makes the page taller than the screen; stays
    // vertically centred when it fits.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - 32),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 60, color: cs.primary),
              ),
              const SizedBox(height: 32),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                  fontSize: 15,
                ),
              ),
              if (child != null) ...[const SizedBox(height: 24), child!],
            ],
          ),
        ),
      ),
    );
  }
}
