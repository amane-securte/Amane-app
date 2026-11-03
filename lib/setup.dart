import 'package:flutter/material.dart';

import 'geo.dart';
import 'i18n.dart';
import 'store.dart';
import 'theme.dart';

/// Écran d'inscription (premier lancement) et de réglages.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.app, required this.first});
  final AppState app;
  final bool first;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.app.name);
  late final _phone = TextEditingController(text: widget.app.phone);
  late final _site = TextEditingController(text: widget.app.site);
  late final _radius =
      TextEditingController(text: widget.app.radius.toString());
  late Fix? _siteFix = widget.app.siteFix;
  bool _locating = false;

  T get t => T(widget.app.lang);

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _site.dispose();
    _radius.dispose();
    super.dispose();
  }

  Future<void> _captureSite() async {
    setState(() => _locating = true);
    final r = await getFix();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (r.fix != null) _siteFix = r.fix;
    });
    if (r.error != null) {
      final msg = switch (r.error!) {
        GeoErr.serviceOff => t('gps_off'),
        GeoErr.denied || GeoErr.deniedForever => t('gps_denied'),
        GeoErr.timeout => t('gps_timeout'),
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), backgroundColor: warn));
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final r = int.tryParse(_radius.text.trim()) ?? 200;
    await widget.app.saveProfile(
      name: _name.text,
      phone: _phone.text,
      site: _site.text,
      radius: r < 20 ? 20 : r,
      siteFix: _siteFix,
    );
    if (!mounted) return;
    if (!widget.first) Navigator.pop(context);
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? t('required') : null;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.first ? 'AMANE' : t('settings')),
        actions: [
          TextButton(
            onPressed: () => app.setLang(app.lang == 'ar' ? 'fr' : 'ar'),
            child: Text(t('lang_btn'),
                style: const TextStyle(color: Color(0xFFFBF6EA))),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.first) ...[
                Center(child: Image.asset('assets/logo.png', height: 96)),
                const SizedBox(height: 12),
                Text(t('setup_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(t('setup_sub'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted)),
                const SizedBox(height: 20),
              ],
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: t('name')),
                textInputAction: TextInputAction.next,
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: InputDecoration(labelText: t('phone')),
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _site,
                decoration: InputDecoration(labelText: t('site')),
                textInputAction: TextInputAction.next,
                validator: _req,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _locating ? null : _captureSite,
                child: _locating
                    ? Text(t('locating'))
                    : Text(t('site_here'), textAlign: TextAlign.center),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _siteFix == null
                      ? t('site_unset')
                      : t('site_set', {'a': _siteFix!.acc.round().toString()}),
                  style: TextStyle(
                      color: _siteFix == null ? muted : okGreen, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _radius,
                decoration: InputDecoration(labelText: t('radius')),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(t('save'), style: const TextStyle(fontSize: 17)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
