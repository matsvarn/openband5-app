import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../gps/route_models.dart';
import '../gps/route_tracker.dart';
import '../ui2/activity/tiles.dart' show kOsmAttribution;
import 'alp_tokens.dart';
import 'session.dart';
import 'theme.dart';

/// Live state of a distance activity. Pauses are explicit user intervals;
/// absent heart rate is never a pause (B19). [pausedSec] and [elapsedSec]
/// are kept apart so the saved duration cannot silently swap one for the
/// other.
class LiveRun {
  final int elapsedSec, pausedSec, laps;
  final double? distanceM;
  final int? heartRate, zone;
  final bool paused, gps;
  const LiveRun({
    required this.elapsedSec,
    this.pausedSec = 0,
    this.laps = 0,
    this.distanceM,
    this.heartRate,
    this.zone,
    this.paused = false,
    this.gps = false,
  });
  int get activeSec => elapsedSec - pausedSec;
}

class OpenBandRunLive extends StatelessWidget {
  final ValueListenable<LiveRun> run;
  final RouteTracker? tracker;
  final TileProvider? tileProvider;

  /// Basemap tiles are an outbound request; they are drawn only when the user
  /// has allowed them (tiles.dart `mapTilesAllowed`). Default off.
  final bool mapAllowed;
  final String label;
  final VoidCallback? onPause, onResume, onLap, onFinish, onCollapse;
  const OpenBandRunLive({
    super.key,
    required this.run,
    this.tracker,
    this.tileProvider,
    this.mapAllowed = false,
    this.label = 'Laufen',
    this.onPause,
    this.onResume,
    this.onLap,
    this.onFinish,
    this.onCollapse,
  });
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return ValueListenableBuilder<LiveRun>(
      valueListenable: run,
      builder: (context, r, _) => Scaffold(
        backgroundColor: p.canvas,
        appBar: AppBar(
          backgroundColor: p.canvas,
          leading: IconButton(
            tooltip: 'Einklappen',
            onPressed: onCollapse ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(LucideIcons.chevronDown, size: 22),
          ),
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: r.paused ? p.gap : p.strain,
                  shape: BoxShape.circle,
                ),
              ),
              Text(label, style: p.text(18, weight: FontWeight.w700)),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Semantics(
                label: r.gps ? 'GPS aktiv' : 'GPS nicht verfügbar',
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    spacing: 6,
                    children: [
                      Icon(
                        LucideIcons.locate,
                        size: 14,
                        color: r.gps ? p.recovery : p.gap,
                      ),
                      Text('GPS', style: p.text(13, weight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  OBLiveMetrics(run: r),
                  const SizedBox(height: 10),
                  Container(
                    height: 200,
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.bottomLeft,
                    padding: tracker != null && r.gps && mapAllowed
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.sleepTint,
                      borderRadius: BorderRadius.circular(AlpRadius.card),
                    ),
                    child: tracker != null && r.gps && mapAllowed
                        ? _LiveRouteMap(
                            tracker: tracker!,
                            tileProvider: tileProvider,
                          )
                        : Container(
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.card,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              !r.gps
                                  ? 'Karte ohne GPS nicht verfügbar'
                                  : mapAllowed
                                  ? 'Karte'
                                  : 'Karte aus · Kartendaten in den Einstellungen erlauben',
                              style: p.text(
                                12,
                                weight: FontWeight.w600,
                                color: p.muted,
                              ),
                            ),
                          ),
                  ),
                  if (r.pausedSec > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, left: 4),
                      child: Text(
                        'davon ${obClock(r.pausedSec)} pausiert',
                        style: p.text(13, color: p.muted),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: r.paused
                          ? OBAction(
                              'Beenden',
                              secondary: true,
                              onPressed: onFinish,
                            )
                          : OBAction(
                              'Runde',
                              secondary: true,
                              onPressed: onLap,
                            ),
                    ),
                    Expanded(
                      flex: 2,
                      child: OBAction(
                        r.paused ? 'Weiter' : 'Pause',
                        onPressed: r.paused ? onResume : onPause,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live route over CARTO raster tiles (the app's single interactive tile
/// provider — the pubspec note covers why CARTO and not OSM directly).
/// [RouteVertex.gapBefore] breaks the polyline rather than drawing a straight
/// line across a recording gap.
class _LiveRouteMap extends StatefulWidget {
  final RouteTracker tracker;
  final TileProvider? tileProvider;
  const _LiveRouteMap({required this.tracker, this.tileProvider});
  @override
  State<_LiveRouteMap> createState() => _LiveRouteMapState();
}

class _LiveRouteMapState extends State<_LiveRouteMap> {
  final _controller = MapController();
  bool _ready = false;

  List<LatLng> get _pts => [for (final v in widget.tracker.path.value) v.pos];

  void _refit() {
    if (!_ready) return;
    final pts = _pts;
    if (pts.length < 2) return;
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(28),
        maxZoom: 17,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.tracker.path.addListener(_refit);
  }

  @override
  void dispose() {
    widget.tracker.path.removeListener(_refit);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    return ValueListenableBuilder<List<RouteVertex>>(
      valueListenable: widget.tracker.path,
      builder: (context, path, _) => ValueListenableBuilder<LatLng?>(
        valueListenable: widget.tracker.current,
        builder: (context, current, _) {
          // One polyline per contiguous segment: a gap vertex opens a new one.
          final polylines = <Polyline>[];
          var seg = <LatLng>[];
          for (final v in path) {
            if (v.gapBefore && seg.isNotEmpty) {
              polylines.add(
                Polyline(points: seg, strokeWidth: 4, color: p.strain),
              );
              seg = <LatLng>[];
            }
            seg.add(v.pos);
          }
          if (seg.isNotEmpty) {
            polylines.add(
              Polyline(points: seg, strokeWidth: 4, color: p.strain),
            );
          }
          return FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCameraFit: _pts.length >= 2
                  ? CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(_pts),
                      padding: const EdgeInsets.all(28),
                      maxZoom: 17,
                    )
                  : null,
              initialCenter:
                  current ?? (_pts.isNotEmpty ? _pts.last : const LatLng(0, 0)),
              initialZoom: 15,
              onMapReady: () {
                _ready = true;
                _refit();
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.openstrap.edge',
                tileProvider: widget.tileProvider,
              ),
              PolylineLayer(polylines: polylines),
              if (current != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: current,
                      width: 16,
                      height: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.strain,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.card, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              const SimpleAttributionWidget(
                source: Text(kOsmAttribution),
                alignment: Alignment.bottomLeft,
              ),
            ],
          );
        },
      ),
    );
  }
}

class OBLiveMetrics extends StatelessWidget {
  final LiveRun run;
  const OBLiveMetrics({super.key, required this.run});
  @override
  Widget build(BuildContext context) {
    final p = OB.of(context);
    final r = run;
    Widget metric(String value, String label, {Color? color}) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: p.text(
              26,
              weight: FontWeight.w800,
              display: true,
              color: color,
            ),
          ),
          Text(
            label,
            style: p.text(12, weight: FontWeight.w600, color: p.muted),
          ),
        ],
      ),
    );
    return OBCard(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
      child: Column(
        spacing: 12,
        children: [
          Column(
            children: [
              Text(
                r.distanceM == null
                    ? '—'
                    : obNumber(r.distanceM! / 1000, digits: 2),
                style: p.text(64, weight: FontWeight.w800, display: true),
              ),
              Text(
                'km',
                style: p.text(14, weight: FontWeight.w600, color: p.muted),
              ),
              if (r.laps > 0)
                Container(
                  height: 24,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.well,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Runde ${r.laps}',
                    style: p.text(13, weight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              metric(obClock(r.activeSec), 'Zeit'),
              metric(obPace(r.distanceM, r.activeSec), 'Tempo /km'),
              metric(
                r.heartRate == null
                    ? '—'
                    : '${r.heartRate}${r.zone == null ? '' : ' · Z${r.zone}'}',
                'Puls',
                color: r.heartRate == null ? p.gap : p.pulse,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
