import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/traffic_camera.dart';
import '../models/weather_station.dart';
import '../providers/cameras_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/feed.dart';
import '../providers/weather_provider.dart';
import '../router/route_names.dart';
import '../services/prefs.dart';
import '../theme/app_theme.dart';
import '../widgets/camera_sheet.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/webcam_image.dart';
import '../widgets/weather_details.dart';
import '../widgets/live_webcam_image.dart';

/// Section title for the favourites group, rendered as full-width webcam cards.
const String _kFavoritesTitle = '★ Priljubljene';

/// Restricts the list to stations of a given kind.
enum _KindFilter { all, weather, camera }

/// List of all stations with a webcam thumbnail and temperature. Supports
/// text search, kind filtering, and a favourites-only view.
class ListTab extends ConsumerStatefulWidget {
  const ListTab({super.key});

  @override
  ConsumerState<ListTab> createState() => _ListTabState();
}

class _ListTabState extends ConsumerState<ListTab> {
  String _query = '';
  bool _onlyFavorites = false;
  bool _showDarsCameras = true;
  _KindFilter _kind = _KindFilter.all;
  int _refreshKey = DateTime.now().millisecondsSinceEpoch;

  /// Refresh data and bust the webcam/camera image cache so thumbnails reload.
  Future<void> _onRefresh() async {
    setState(() => _refreshKey = DateTime.now().millisecondsSinceEpoch);
    await Future.wait([
      ref.read(weatherProvider.notifier).refresh(),
      ref.read(camerasProvider.notifier).refresh(),
    ]);
  }

  int _lastFavCount = 0;

  @override
  void initState() {
    super.initState();
    // Restore saved filters.
    _onlyFavorites = Prefs.getBool('list.onlyFavorites', false);
    _showDarsCameras = Prefs.getBool('list.darsCameras', true);
    final ki = Prefs.getInt('list.kind', 0);
    _kind = _KindFilter.values[ki.clamp(0, _KindFilter.values.length - 1)];
    final favs = ref.read(favoritesProvider);
    _lastFavCount = favs.length;
    // Default to the favourites view if the user has some — but only when
    // they haven't set an explicit preference before.
    if (!Prefs.has('list.onlyFavorites') && favs.isNotEmpty) {
      _onlyFavorites = true;
    }
  }

  void _saveListFilters() {
    Prefs.setBool('list.onlyFavorites', _onlyFavorites);
    Prefs.setBool('list.darsCameras', _showDarsCameras);
    Prefs.setInt('list.kind', _kind.index);
  }

  /// Auto-switch to the favourites view the moment the first favourite is added,
  /// and back to the full list when the last one is removed.
  void _onFavoritesChanged(Set<int> favs) {
    final count = favs.length;
    if (_lastFavCount == 0 && count > 0 && !_onlyFavorites) {
      setState(() => _onlyFavorites = true);
      _saveListFilters();
    } else if (count == 0 && _onlyFavorites) {
      setState(() => _onlyFavorites = false);
      _saveListFilters();
    }
    _lastFavCount = count;
  }

  bool _matches(WeatherStation s, Set<int> favs) {
    if (_query.isNotEmpty && !s.name.toLowerCase().contains(_query)) {
      return false;
    }
    if (_onlyFavorites && !favs.contains(s.stationId)) return false;
    switch (_kind) {
      case _KindFilter.weather:
        if (!s.hasWeather) return false;
      case _KindFilter.camera:
        if (s.hasWeather) return false;
      case _KindFilter.all:
        break;
    }
    return true;
  }

  bool _matchesCamera(TrafficCamera c) {
    if (_query.isEmpty) return true;
    return c.title.toLowerCase().contains(_query) ||
        c.region.toLowerCase().contains(_query);
  }

  /// Groups the filtered stations and DARS cameras into section cards. In
  /// favourites-only mode, favourite stations are shown as full-width webcam
  /// heroes; otherwise favourites lead, then everything (stations + cameras) is
  /// grouped alphabetically by name. Items are [WeatherStation] or
  /// [TrafficCamera].
  List<({String title, List<Object> items})> _buildGroups(
    List<WeatherStation> stations,
    List<TrafficCamera> cameras,
    Set<int> favs,
  ) {
    final groups = <({String title, List<Object> items})>[];

    if (_onlyFavorites) {
      if (stations.isNotEmpty) {
        groups.add((title: _kFavoritesTitle, items: List<Object>.of(stations)));
      }
      return groups;
    }

    final favStations = stations
        .where((s) => favs.contains(s.stationId))
        .toList();
    if (favStations.isNotEmpty) {
      groups.add((
        title: _kFavoritesTitle,
        items: List<Object>.of(favStations),
      ));
    }

    // Merge stations + cameras, sorted by display name.
    final entries = <({String name, Object item})>[
      for (final s in stations) (name: s.name, item: s),
      for (final c in cameras) (name: c.title, item: c),
    ]..sort((a, b) => compareSlovenian(a.name, b.name));

    String? letter;
    List<Object>? bucket;
    for (final e in entries) {
      final initial = e.name.isNotEmpty ? e.name[0].toUpperCase() : '#';
      if (initial != letter) {
        letter = initial;
        bucket = [];
        groups.add((title: initial, items: bucket));
      }
      bucket!.add(e.item);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(favoritesProvider, (_, next) => _onFavoritesChanged(next));
    // No app bar: the "Postaje" tab already labels this screen. Search and
    // filters live at the top of the body instead.
    return AdaptiveScaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  // Native iOS search field; Material text field elsewhere.
                  Expanded(
                    child: PlatformInfo.isIOS
                        ? CupertinoSearchTextField(
                            placeholder: 'Išči postajo ali kamero…',
                            onChanged: (v) =>
                                setState(() => _query = v.toLowerCase().trim()),
                          )
                        : AdaptiveTextField(
                            placeholder: 'Išči postajo ali kamero…',
                            prefixIcon: const Icon(Icons.search),
                            onChanged: (v) =>
                                setState(() => _query = v.toLowerCase().trim()),
                          ),
                  ),
                  const SizedBox(width: 8),
                  FilterButton(
                    activeCount: _activeFilterCount,
                    onTap: _openFilters,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Consumer(
                builder: (context, ref, _) {
                  final provider = ref.watch(weatherProvider);
                  final favs = ref.watch(favoritesProvider);
                  if (provider.isLoading && !provider.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (provider.error != null && !provider.hasData) {
                    return _error(context, provider);
                  }

                  final stations = provider.items
                      .where((s) => _matches(s, favs))
                      .toList();
                  // DARS cameras join the list unless filtered out.
                  final cameras =
                      (_showDarsCameras &&
                          !_onlyFavorites &&
                          _kind != _KindFilter.weather)
                      ? visibleCameras(
                          ref.watch(camerasProvider.select((s) => s.items)),
                          provider.items,
                        ).where(_matchesCamera).toList()
                      : <TrafficCamera>[];

                  if (stations.isEmpty && cameras.isEmpty) {
                    return _empty(context);
                  }

                  final groups = _buildGroups(stations, cameras, favs);

                  return RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.only(
                        top: 4,
                        bottom: 16 + AppTheme.bottomBarContentInset(context),
                      ),
                      itemCount: groups.length,
                      itemBuilder: (context, i) => _SectionCard(
                        title: groups[i].title,
                        items: groups[i].items,
                        refreshKey: _refreshKey,
                        isFavorites: groups[i].title == _kFavoritesTitle,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _activeFilterCount =>
      (_kind != _KindFilter.all ? 1 : 0) +
      (_onlyFavorites ? 1 : 0) +
      (_showDarsCameras ? 0 : 1);

  void _openFilters() {
    final favCount = ref.read(favoritesProvider).length;

    showFilterSheet(
      context: context,
      title: 'Filtri',
      contentBuilder: (setSheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const FilterSectionLabel('Vrsta'),
          // Flutter-drawn segmented control (the native one is a platform view
          // that occludes following content in a sheet).
          PlatformInfo.isIOS
              ? CupertinoSlidingSegmentedControl<int>(
                  groupValue: _kind.index,
                  children: const {
                    0: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Vse'),
                    ),
                    1: Text('Vreme'),
                    2: Text('Kamera'),
                  },
                  onValueChanged: (i) {
                    if (i != null) {
                      setSheet(() {
                        setState(() => _kind = _KindFilter.values[i]);
                        _saveListFilters();
                      });
                    }
                  },
                )
              : SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Vse')),
                    ButtonSegment(value: 1, label: Text('Vreme')),
                    ButtonSegment(value: 2, label: Text('Kamera')),
                  ],
                  selected: {_kind.index},
                  onSelectionChanged: (s) => setSheet(() {
                    setState(() => _kind = _KindFilter.values[s.first]);
                    _saveListFilters();
                  }),
                ),
          const SizedBox(height: 8),
          const FilterSectionLabel('Prikaz'),
          // Whole row toggles and reads as one switch for screen readers.
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              favCount > 0
                  ? 'Samo priljubljene ($favCount)'
                  : 'Samo priljubljene',
              style: const TextStyle(fontSize: 15),
            ),
            value: _onlyFavorites,
            onChanged: (v) => setSheet(() {
              setState(() => _onlyFavorites = v);
              _saveListFilters();
            }),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('DARS kamere', style: TextStyle(fontSize: 15)),
            value: _showDarsCameras,
            onChanged: (v) => setSheet(() {
              setState(() => _showDarsCameras = v);
              _saveListFilters();
            }),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final favoritesEmpty = _onlyFavorites && _query.isEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              favoritesEmpty ? Icons.star_border : Icons.search_off,
              size: 48,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              favoritesEmpty
                  ? 'Ni priljubljenih postaj.\nDodaj jih z zvezdico.'
                  : 'Ni zadetkov.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _error(BuildContext context, FeedState<WeatherStation> provider) {
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
              onPressed: () => ref.read(weatherProvider.notifier).refresh(),
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

/// A native inset-grouped section: a `CupertinoFormSection` card on iOS and a
/// rounded Material card on Android, with an uppercase header above the rows.
class _SectionCard extends StatelessWidget {
  final String title;

  /// Each item is a [WeatherStation] or a [TrafficCamera].
  final List<Object> items;
  final int refreshKey;
  final bool isFavorites;

  const _SectionCard({
    required this.title,
    required this.items,
    required this.refreshKey,
    this.isFavorites = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Favourites get a prominent, full-width webcam hero per station.
    if (isFavorites) {
      final stations = items.whereType<WeatherStation>().toList();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            for (var i = 0; i < stations.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i < stations.length - 1 ? 12 : 0,
                ),
                child: _FavoriteHeroCard(
                  station: stations[i],
                  refreshKey: refreshKey,
                ),
              ),
          ],
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      rows.add(
        item is WeatherStation
            ? _StationRow(station: item, refreshKey: refreshKey)
            : _CameraRow(camera: item as TrafficCamera, refreshKey: refreshKey),
      );
      // iOS draws its own row separators; Android needs explicit hairlines.
      if (!PlatformInfo.isIOS && i < items.length - 1) {
        rows.add(
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 88,
            color: cs.outline.withValues(alpha: 0.3),
          ),
        );
      }
    }

    return AdaptiveFormSection.insetGrouped(
      header: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
      children: rows,
    );
  }
}

/// A modern station row: rounded webcam thumbnail, name + condition, a coloured
/// temperature pill, a favourite toggle, and a disclosure chevron. Transparent
/// so the enclosing section card provides the background.
class _StationRow extends ConsumerWidget {
  final WeatherStation station;
  final int refreshKey;

  const _StationRow({required this.station, required this.refreshKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final temp = station.temperatureC;
    final isFav = ref.watch(
      favoritesProvider.select((s) => s.contains(station.stationId)),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.go(AppRoutes.stationDetail(station.stationId)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 48,
                child: WebcamImage(station: station, refreshKey: refreshKey),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    station.weather == null
                        ? 'Samo kamera'
                        : WeatherFormat.wind(station.weather!),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (temp == null)
              const _KindIcon()
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.temperatureColor(temp),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${temp.round()}°',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Semantics(
              button: true,
              toggled: isFav,
              label: isFav
                  ? 'Odstrani iz priljubljenih'
                  : 'Dodaj med priljubljene',
              child: AdaptiveButton.icon(
                icon: isFav ? Icons.star : Icons.star_border,
                iconColor: isFav
                    ? const Color(0xFFFFB74D)
                    : cs.onSurfaceVariant,
                style: AdaptiveButtonStyle.plain,
                minSize: const Size(_kTrailingActionWidth, 44),
                onPressed: () => ref
                    .read(favoritesProvider.notifier)
                    .toggle(station.stationId),
              ),
            ),
            const _Chevron(),
          ],
        ),
      ),
    );
  }
}

/// A full-width webcam hero for a favourite station: large image with the name
/// and temperature overlaid, plus a star to unfavourite. Tap opens the detail.
class _FavoriteHeroCard extends ConsumerWidget {
  final WeatherStation station;
  final int refreshKey;

  const _FavoriteHeroCard({required this.station, required this.refreshKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final temp = station.temperatureC;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.go(AppRoutes.stationDetail(station.stationId)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.black,
                child: WebcamImage(station: station, refreshKey: refreshKey),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.5, 1.0],
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: Semantics(
                  button: true,
                  label: 'Odstrani iz priljubljenih',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref
                        .read(favoritesProvider.notifier)
                        .toggle(station.stationId),
                    // 48pt hit area around the 32pt visible badge.
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.star,
                          color: Color(0xFFFFB74D),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        station.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          shadows: [
                            Shadow(blurRadius: 6, color: Colors.black87),
                          ],
                        ),
                      ),
                    ),
                    if (temp != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.temperatureColor(temp),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${temp.round()}°',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ] else
                      const Icon(
                        Icons.videocam,
                        color: Colors.white70,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact row for a DARS camera (thumbnail, name, region). Tap opens the
/// camera viewer.
class _CameraRow extends StatelessWidget {
  final TrafficCamera camera;
  final int refreshKey;

  const _CameraRow({required this.camera, required this.refreshKey});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = camera.imageUrlWithBuster(refreshKey);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showCameraSheet(context, camera),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 48,
                child: ColoredBox(
                  color: Colors.black,
                  child: LiveWebcamImage(
                    url: url,
                    // 64x48 thumbnail: decode small, not the full frame.
                    memCacheWidth: 192,
                    fit: BoxFit.cover,
                    placeholder: (_) => const ColoredBox(color: Colors.black),
                    errorWidget: (_) => const Icon(
                      Icons.videocam_off,
                      color: Colors.white38,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    camera.title.isEmpty ? 'Kamera' : camera.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Prefixed so a DARS camera is distinguishable from a
                    // weather station of the same name.
                    [
                      'Kamera DARS',
                      if (camera.description.isNotEmpty)
                        camera.description
                      else if (camera.region.isNotEmpty)
                        camera.region,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const _KindIcon(),
            // Same slot as the station row's star so chevrons line up.
            const SizedBox(width: _kTrailingActionWidth),
            const _Chevron(),
          ],
        ),
      ),
    );
  }
}

/// Width of the trailing action slot (the favourite star) in list rows; rows
/// without an action leave it empty so their icons and chevrons line up.
const double _kTrailingActionWidth = 44;

/// Camera-only marker shown where a station row would show a temperature.
class _KindIcon extends StatelessWidget {
  const _KindIcon();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.videocam,
      size: 20,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.chevron_right,
      size: 20,
      color: Theme.of(context).colorScheme.onSurfaceVariant
          .withValues(alpha: 0.5),
    );
  }
}

/// Slovenian alphabetical order: Č after C, Š after S, Ž after Z (plain
/// code-unit comparison puts them after Z).
const _slAlphabet = 'abcčćdđefghijklmnopqrsštuvwxyzž';

@visibleForTesting
int compareSlovenian(String a, String b) {
  final x = a.toLowerCase(), y = b.toLowerCase();
  final n = x.length < y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final cx = x[i], cy = y[i];
    if (cx == cy) continue;
    final ix = _slAlphabet.indexOf(cx), iy = _slAlphabet.indexOf(cy);
    if (ix >= 0 && iy >= 0) return ix.compareTo(iy);
    return cx.compareTo(cy);
  }
  return x.length.compareTo(y.length);
}
