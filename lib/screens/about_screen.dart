import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/testing.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    });
  }

  Future<void> _open(String url) async {
    bool opened;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on PlatformException {
      opened = false;
    }
    if (!opened && mounted) {
      AdaptiveSnackBar.show(
        context,
        message: 'Povezave ni mogoče odpreti',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  /// Testing runs through Google Play, so only Android users can join.
  bool get _showTesting =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Widget _sectionHeader(String text, ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
    child: Text(
      text,
      style: TextStyle(
        color: cs.onSurfaceVariant,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(title: 'O aplikaciji'),
      // The SafeArea also clears the iOS 26 native toolbar (the scaffold adds
      // its height to the top padding), so no extra app-bar inset is needed.
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            // Pushed above the tab bar; only the home indicator to clear.
            20 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Icon(Icons.traffic, size: 64, color: cs.primary),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Prometnik',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (_version.isNotEmpty)
              Center(
                child: Text(
                  'Različica $_version',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'Prometnik zbere promet na slovenskih cestah na enem mestu: '
              'dogodke (zapore, zastoje, dela), kamere v živo, vreme in stanje '
              'cest, potovalne čase na glavnih poteh ter opozorila za ceste, '
              'ki jih spremljaš, in dogodke v tvoji bližini. Podatki se '
              'samodejno osvežujejo.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (_showTesting) ...[
              const SizedBox(height: 24),
              const Divider(),
              _sectionHeader('PREIZKUŠANJE', cs),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Nove različice preizkusi pred drugimi: pridruži se skupini '
                  'preizkuševalcev, nato v Googlu Play potrdi sodelovanje.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              AdaptiveListTile(
                leading: const Icon(Icons.group_add_outlined),
                title: const Text('1. Pridruži se skupini'),
                subtitle: const Text('Google Skupine: prometnik-testers'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _open(testersGroupUrl),
              ),
              AdaptiveListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('2. Postani preizkuševalec'),
                subtitle: const Text('Google Play'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _open(playTestingOptInUrl),
              ),
            ],
            const SizedBox(height: 24),
            const Divider(),
            _sectionHeader('VIRI PODATKOV', cs),
            AdaptiveListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: const Text('Dogodki, kamere, potovalni časi'),
              subtitle: const Text('DARS / promet.si'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open('https://www.promet.si/'),
            ),
            AdaptiveListTile(
              leading: const Icon(Icons.thermostat),
              title: const Text('Vreme in kamere postaj'),
              subtitle: const Text('ceste.si'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open('https://www.ceste.si/Vreme/'),
            ),
            AdaptiveListTile(
              leading: const Icon(Icons.ac_unit),
              title: const Text('Stanje cest'),
              subtitle: const Text('DRSI CVIS'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open('http://drsi.cgs-labs.si/CVIS'),
            ),
            AdaptiveListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Vremenske kamere'),
              subtitle: const Text('ARSO'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open('https://meteo.arso.gov.si/'),
            ),
            AdaptiveListTile(
              leading: const Icon(Icons.map),
              title: const Text('Cestno omrežje in karta'),
              subtitle: const Text('© OpenStreetMap contributors (ODbL)'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open('https://www.openstreetmap.org/copyright'),
            ),
            AdaptiveListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Turistična karta'),
              subtitle: const Text('© Seznam.cz (mapy.com)'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open('https://mapy.com/'),
            ),
            const SizedBox(height: 24),
            Text(
              'Podatki so informativne narave. Aplikacija ni uradni produkt DARS, '
              'DRSI ali ARSO.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
