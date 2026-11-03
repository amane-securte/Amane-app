import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'geo.dart';
import 'i18n.dart';
import 'setup.dart';
import 'store.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.app});
  final AppState app;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;

  AppState get app => widget.app;
  T get t => T(app.lang);

  void _snack(String msg, {Color? color, SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        action: action,
        duration: const Duration(seconds: 5),
      ));
  }

  Future<GeoResult> _locate({int seconds = 15}) async {
    setState(() => _busy = true);
    final r = await getFix(seconds: seconds);
    if (mounted) setState(() => _busy = false);
    return r;
  }

  void _gpsError(GeoErr e) {
    final msg = switch (e) {
      GeoErr.serviceOff => t('gps_off'),
      GeoErr.denied || GeoErr.deniedForever => t('gps_denied'),
      GeoErr.timeout => t('gps_timeout'),
    };
    _snack(msg,
        color: warn,
        action: e == GeoErr.timeout
            ? null
            : SnackBarAction(
                label: t('open_settings'),
                textColor: Colors.white,
                onPressed: () => openGeoSettings(e),
              ));
  }

  /// Texte et couleur décrivant une position par rapport au site.
  (String, Color) _locInfo(Fix? f) {
    if (f == null) return (t('no_gps'), muted);
    final d = app.distToSite(f);
    if (d == null) return (t('no_site'), muted);
    final on = app.onSite(f) ?? false;
    return (
      t(on ? 'on_site' : 'off_site', {'d': d.round().toString()}),
      on ? okGreen : danger
    );
  }

  Future<void> _punch() async {
    final r = await _locate();
    if (!mounted) return;
    final wasOn = app.current != null;
    if (wasOn) {
      await app.punchOut(r.fix);
    } else {
      await app.punchIn(r.fix);
    }
    if (!mounted) return;
    if (r.error != null) {
      _gpsError(r.error!);
    } else {
      final (txt, col) = _locInfo(r.fix);
      _snack('${t(wasOn ? 'saved_out' : 'saved_in')} · $txt', color: col);
    }
  }

  Future<void> _sos() async {
    const types = ['assault', 'intrusion', 'fire', 'medical', 'other'];
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t('sos_title'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            for (final ty in types)
              ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: danger),
                title: Text(t('ty_$ty'),
                    style: const TextStyle(fontSize: 17)),
                onTap: () => Navigator.pop(ctx, ty),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;

    // En urgence, on n'attend pas le GPS plus de 10 secondes.
    final r = await _locate(seconds: 10);
    if (!mounted) return;
    final f = r.fix;
    final text = t('sms_text', {
      'type': t('ty_$type'),
      'site': app.site,
      'name': app.name,
      'pos': f == null ? '' : ' - ${f.mapUrl}',
      'time': hm(DateTime.now()),
    });
    final uri =
        Uri.parse('sms:$controlPhone?body=${Uri.encodeComponent(text)}');
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    _snack(t(opened ? 'sos_ready' : 'sms_fail'),
        color: opened ? navy : danger);
  }

  Future<void> _call() async {
    try {
      await launchUrl(Uri.parse('tel:$controlPhone'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cur = app.current;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Image.asset('assets/logo.png', height: 36),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AMANE',
                    style: TextStyle(
                        fontSize: 20,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600)),
                Text(t('app_sub'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFFD1A850))),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => app.setLang(app.lang == 'ar' ? 'fr' : 'ar'),
            child: Text(t('lang_btn'),
                style: const TextStyle(color: Color(0xFFFBF6EA))),
          ),
          IconButton(
            tooltip: t('settings'),
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SetupScreen(app: app, first: false)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusCard(cur),
            const SizedBox(height: 14),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: _busy ? null : _punch,
                icon: Icon(cur == null ? Icons.login : Icons.logout),
                label: Text(cur == null ? t('btn_in') : t('btn_out'),
                    style: const TextStyle(fontSize: 18)),
              ),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text(t('locating')),
                  ],
                ),
              ),
            const SizedBox(height: 28),
            Center(child: _sosButton()),
            const SizedBox(height: 8),
            Center(
                child: Text(t('sos_hint'),
                    style: const TextStyle(color: muted))),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                onPressed: _call,
                icon: const Icon(Icons.phone),
                label: Text(t('call_control')),
              ),
            ),
            const SizedBox(height: 28),
            Text(t('history'),
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (app.history.isEmpty)
              Text(t('empty_history'), style: const TextStyle(color: muted))
            else
              ...app.history.take(15).map(_historyTile),
            const SizedBox(height: 20),
            Text(t('test_note'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(Punch? cur) {
    final on = cur != null;
    final (locTxt, locCol) = cur != null ? _locInfo(cur.inFix) : ('', muted);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(app.name,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            if (app.site.isNotEmpty)
              Text(app.site, style: const TextStyle(color: muted)),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(on ? Icons.shield : Icons.shield_outlined,
                    color: on ? okGreen : muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    cur != null ? t('status_on', {'t': hm(cur.inAt)}) : t('status_off'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: on ? okGreen : ink),
                  ),
                ),
              ],
            ),
            if (on) ...[
              const SizedBox(height: 6),
              _pill('📍 $locTxt', locCol),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 13)),
      );

  Widget _sosButton() => SizedBox(
        width: 170,
        height: 170,
        child: ElevatedButton(
          onPressed: _busy ? null : _sos,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: danger,
            foregroundColor: Colors.white,
            disabledBackgroundColor: danger.withValues(alpha: 0.5),
            elevation: 6,
          ),
          child: const Text('SOS',
              style: TextStyle(
                  fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: 3)),
        ),
      );

  Widget _historyTile(Punch p) {
    final out = p.outAt;
    final mins = out == null ? 0 : out.difference(p.inAt).inMinutes;
    final (inTxt, inCol) = _locInfo(p.inFix);
    final (outTxt, outCol) = _locInfo(p.outFix);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(dm(p.inAt),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                      '${hm(p.inAt)} → ${out == null ? '…' : hm(out)}'),
                ),
                const Spacer(),
                Text(t('dur', {'h': '${mins ~/ 60}', 'm': '${mins % 60}'}),
                    style: const TextStyle(color: muted)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _pill('${t('arrival')}: $inTxt', inCol),
                _pill('${t('departure')}: $outTxt', outCol),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
