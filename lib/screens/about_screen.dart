import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

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
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(title: 'O aplikaciji'),
      // iOS: keep content clear of the translucent navigation bar.
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20 + AppTheme.appBarContentInset(),
            20,
            20,
          ),
          children: [
            Icon(Icons.thermostat, size: 64, color: cs.primary),
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
              'Prikazuje temperaturo in spletne kamere vremenskih postaj na '
              'slovenskih cestah. Podatki se osvežujejo vsakih 10 minut.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            const Divider(),
            AdaptiveListTile(
              leading: const Icon(Icons.public),
              title: const Text('Vir podatkov'),
              subtitle: const Text('ceste.si (DARS)'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open('https://www.ceste.si/Vreme/'),
            ),
            AdaptiveListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Kamere'),
              subtitle: const Text('kamere.dars.si'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open('https://kamere.dars.si/'),
            ),
            const SizedBox(height: 24),
            Text(
              'Podatki so informativne narave. Aplikacija ni uradni produkt DARS.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
