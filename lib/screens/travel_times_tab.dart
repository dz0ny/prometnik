import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/travel_time.dart';
import '../providers/travel_times_provider.dart';
import '../theme/app_theme.dart';

/// Lists travel times ("potovalni časi") for the main routes, with the current
/// duration and any delay, from the promet.si data channel.
class TravelTimesTab extends StatelessWidget {
  const TravelTimesTab({super.key});

  static Color _statusColor(TravelStatus s) => switch (s) {
    TravelStatus.normal => const Color(0xFF66BB6A), // green
    TravelStatus.slow => const Color(0xFFFFB300), // amber
    TravelStatus.congested => const Color(0xFFFB8C00), // orange
    TravelStatus.closed => const Color(0xFFE53935), // red
  };

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      body: SafeArea(
        bottom: false,
        child: Consumer<TravelTimesProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading && !provider.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.error != null && !provider.hasData) {
              return _error(context, provider);
            }
            if (provider.items.isEmpty) {
              return _empty(context);
            }

            return RefreshIndicator(
              onRefresh: provider.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  top: 4,
                  bottom: 16 + AppTheme.bottomBarContentInset(context),
                ),
                children: [
                  AdaptiveFormSection.insetGrouped(
                    header: Text(
                      'POTOVALNI ČASI',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    children: [
                      for (var i = 0; i < provider.items.length; i++) ...[
                        _TravelRow(item: provider.items[i]),
                        if (!PlatformInfo.isIOS &&
                            i < provider.items.length - 1)
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 28,
                            color: Theme.of(
                              context,
                            ).colorScheme.outline.withValues(alpha: 0.3),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Ni podatkov o potovalnih časih.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _error(BuildContext context, TravelTimesProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(provider.error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            AdaptiveButton.child(
              onPressed: provider.refresh,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 18),
                  SizedBox(width: 8),
                  Text('Poskusi znova'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelRow extends StatelessWidget {
  final TravelTime item;

  const _TravelRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = TravelTimesTab._statusColor(item.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.route,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          if (item.isClosed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Zaprto',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.actualText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (item.hasDelay)
                  Text(
                    '+${item.delayText}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  )
                else
                  Text(
                    'tekoče',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
