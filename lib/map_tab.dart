import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'data.dart';
import 'geo.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Centre de Nouakchott, vue par défaut.
const _nouakchott = LatLng(18.0858, -15.9785);

/// Carte en direct : sites, agents en service (dernier pointage) et alertes.
class MapTab extends StatefulWidget {
  const MapTab({super.key, required this.t, required this.sites});
  final T t;
  final List<Site> sites;

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  late final Stream<QueryMap> _alerts = db
      .collection('alerts')
      .where('status', whereIn: ['open', 'taken']).snapshots();
  late final Stream<QueryMap> _punches = db
      .collection('punches')
      .where('inAt',
          isGreaterThan: Timestamp.fromDate(
              DateTime.now().subtract(const Duration(hours: 24))))
      .snapshots();
  final _map = MapController();

  T get t => widget.t;

  LatLng _ll(Fix f) => LatLng(f.lat, f.lng);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryMap>(
      stream: _alerts,
      builder: (context, aSnap) {
        final alerts = (aSnap.data?.docs ?? const [])
            .map((d) => AlertDoc(d.id, d.data()))
            .where((a) => a.fix != null)
            .toList();
        return StreamBuilder<QueryMap>(
          stream: _punches,
          builder: (context, pSnap) {
            final onDuty = (pSnap.data?.docs ?? const [])
                .map((d) => PunchDoc(d.id, d.data()))
                .where((p) => p.open && p.bestFix != null)
                .toList();
            final sites = widget.sites.where((s) => s.fix != null).toList();
            final markers = <Marker>[
              for (final s in sites)
                _marker(_ll(s.fix!), Icons.location_city, navy, 34,
                    () => _sheet(s.name, t('legend_site'), s.fix!, null)),
              for (final p in onDuty)
                _marker(
                    _ll(p.bestFix!),
                    Icons.person_pin_circle,
                    p.inOk == false ? warn : okGreen,
                    40,
                    () => _sheet(
                        p.name,
                        '${p.siteName} · ${t('status_on', {'t': hm(p.inAt)})}'
                            '${p.lastAt == null ? '' : ' · ${t('last_seen', {'t': hm(p.lastAt!)})}'}',
                        p.bestFix!,
                        p.phone)),
              for (final a in alerts)
                _marker(
                    _ll(a.fix!),
                    Icons.warning_rounded,
                    danger,
                    48,
                    () => _sheet(
                        '🚨 ${t(a.fromClient ? 'need_${a.type}' : 'ty_${a.type}')}',
                        '${a.name} · ${a.siteName} · ${hm(a.at)}',
                        a.fix!,
                        a.phone)),
            ];
            return Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: const MapOptions(
                    initialCenter: _nouakchott,
                    initialZoom: 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'mr.amane.securite',
                    ),
                    MarkerLayer(markers: markers),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                // Légende et compteurs
                PositionedDirectional(
                  top: 10,
                  start: 10,
                  end: 10,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _legend(Icons.warning_rounded, danger,
                              '${t('legend_alerts')} (${alerts.length})'),
                          _legend(Icons.person_pin_circle, okGreen,
                              '${t('legend_guards')} (${onDuty.length})'),
                          _legend(Icons.location_city, navy,
                              '${t('legend_sites')} (${sites.length})'),
                        ],
                      ),
                    ),
                  ),
                ),
                // Recentrer sur tous les points
                PositionedDirectional(
                  bottom: 24,
                  end: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'fit',
                    tooltip: t('fit_all'),
                    onPressed: () => _fit(markers.map((m) => m.point).toList()),
                    child: const Icon(Icons.center_focus_strong),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _fit(List<LatLng> pts) {
    if (pts.isEmpty) {
      _map.move(_nouakchott, 12);
    } else if (pts.length == 1) {
      _map.move(pts.first, 15);
    } else {
      _map.fitCamera(CameraFit.coordinates(
          coordinates: pts, padding: const EdgeInsets.all(60)));
    }
  }

  Marker _marker(LatLng p, IconData icon, Color color, double size,
          VoidCallback onTap) =>
      Marker(
        point: p,
        width: size,
        height: size,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: onTap,
          child: Icon(icon, color: color, size: size, shadows: const [
            Shadow(color: Colors.white, blurRadius: 6),
          ]),
        ),
      );

  Widget _legend(IconData icon, Color color, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12.5)),
        ],
      );

  void _sheet(String title, String sub, Fix f, String? phone) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(sub, style: const TextStyle(color: muted)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => openUrl(f.mapUrl),
                    icon: const Icon(Icons.directions),
                    label: Text(t('directions')),
                  ),
                  if (phone != null && phone.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => openUrl('tel:$phone'),
                      icon: const Icon(Icons.phone),
                      label: Text(t('call')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
