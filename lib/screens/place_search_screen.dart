import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../routing/saved_route.dart';
import '../services/location_service.dart';
import '../services/place_search_service.dart';

/// Full-screen place search for a route's start, stop or end. Pops with the
/// picked [RoutePlace], or null.
class PlaceSearchScreen extends StatefulWidget {
  final String title;
  final PlaceSearchService service;

  PlaceSearchScreen({
    super.key,
    required this.title,
    PlaceSearchService? service,
  }) : service = service ?? PlaceSearchService();

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PlaceHit> _hits = const [];
  bool _loading = false;
  bool _locating = false;
  String? _error;
  int _token = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  void _search(String q) {
    final token = ++_token;
    if (q.trim().length < 2) {
      setState(() {
        _hits = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    unawaited(
      widget.service
          .search(q)
          .then((hits) {
            if (!mounted || token != _token) return;
            setState(() {
              _hits = hits;
              _loading = false;
              _error = hits.isEmpty ? 'Ni zadetkov.' : null;
            });
          })
          .catchError((Object e) {
            if (!mounted || token != _token) return;
            setState(() {
              _loading = false;
              _error = 'Iskanje ni uspelo. Preverite povezavo.';
            });
          }),
    );
  }

  void _useMyLocation() {
    setState(() => _locating = true);
    unawaited(
      _locate().catchError((Object _) {
        if (!mounted) return;
        setState(() {
          _locating = false;
          _error = 'Lokacije ni bilo mogoče določiti.';
        });
      }),
    );
  }

  Future<void> _locate() async {
    final status = await LocationService.instance.requestPermission();
    final pos = status == LocationStatus.granted
        ? await LocationService.instance.current()
        : null;
    if (!mounted) return;
    if (pos == null) {
      setState(() {
        _locating = false;
        _error = 'Lokacija ni na voljo. Dovolite dostop do lokacije.';
      });
      return;
    }
    Navigator.of(context)
        .pop(RoutePlace('Moja lokacija', LatLng(pos.latitude, pos.longitude)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: widget.title),
      body: SafeArea(
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: _search,
                  decoration: InputDecoration(
                    hintText: 'Kraj, ulica ali naslov',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: _locating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.my_location, color: cs.primary),
                title: const Text('Moja lokacija'),
                onTap: _locating ? null : _useMyLocation,
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: _hits.length,
                  itemBuilder: (context, i) {
                    final h = _hits[i];
                    return ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(h.place.name),
                      subtitle: h.subtitle.isEmpty ? null : Text(h.subtitle),
                      onTap: () => Navigator.of(context).pop(h.place),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Iskanje: Photon (komoot), podatki © OpenStreetMap',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
