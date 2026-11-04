import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'data.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Connexion et création de compte (téléphone ou e-mail + mot de passe).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.prefs});
  final Prefs prefs;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  bool _hide = true;

  T get t => T(widget.prefs.lang);

  @override
  void dispose() {
    _id.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  String _err(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
        case 'invalid-email':
          return t('err_cred');
        case 'email-already-in-use':
          return t('err_exists');
        case 'weak-password':
          return t('err_weak');
        case 'network-request-failed':
          return t('err_net');
      }
      return t('err_generic', {'e': e.code});
    }
    return t('err_generic', {'e': '$e'});
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final auth = FirebaseAuth.instance;
    final email = loginEmail(_id.text);
    try {
      if (_signup) {
        final cred = await auth.createUserWithEmailAndPassword(
            email: email, password: _pass.text);
        final u = cred.user!;
        final name = _name.text.trim();
        await u.updateDisplayName(name);
        await db.collection('users').doc(u.uid).set({
          'name': name,
          'phone': _id.text.contains('@') ? '' : _id.text.trim(),
          'email': email,
          'role': email == ownerEmail ? 'admin' : 'pending',
          'createdAt': Timestamp.now(),
        });
      } else {
        await auth.signInWithEmailAndPassword(
            email: email, password: _pass.text);
      }
    } catch (e) {
      if (mounted) {
        snack(context, _err(e), color: danger);
        // Compte déjà existant : on bascule tout seul sur « Connexion ».
        if (e is FirebaseAuthException && e.code == 'email-already-in-use') {
          setState(() => _signup = false);
        }
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Envoie un lien de réinitialisation à une vraie adresse e-mail.
  /// Les agents (connexion par téléphone) passent par l'administration.
  Future<void> _forgot() async {
    final id = _id.text.trim();
    if (!id.contains('@')) {
      snack(context, t('forgot_phone'), color: warn);
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: loginEmail(id));
      if (mounted) snack(context, t('forgot_sent', {'e': id}), color: okGreen);
    } catch (e) {
      if (mounted) snack(context, _err(e), color: danger);
    }
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? t('required') : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: amaneAppBar(context, widget.prefs, showLogout: false),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 8),
              Center(child: Image.asset('assets/logo_full_t.png', height: 210)),
              if (kIsWeb)
                Card(
                  color: const Color(0xFFFFF8E1),
                  child: ListTile(
                    leading: const Icon(Icons.phone_iphone, color: Color(0xFFA9812F)),
                    title: Text(t('web_install_title'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(t('web_install')),
                  ),
                ),
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(t('login'))),
                  ButtonSegment(value: true, label: Text(t('signup'))),
                ],
                selected: {_signup},
                onSelectionChanged: (s) => setState(() => _signup = s.first),
              ),
              const SizedBox(height: 20),
              if (_signup) ...[
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: t('name')),
                  textInputAction: TextInputAction.next,
                  validator: _req,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _id,
                decoration: InputDecoration(
                    labelText: t('identifier'), hintText: '22 00 00 00'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass,
                obscureText: _hide,
                decoration: InputDecoration(
                  labelText: t('password'),
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.length < 6) ? t('err_weak') : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_signup ? t('btn_signup') : t('btn_login'),
                          style: const TextStyle(fontSize: 17)),
                ),
              ),
              if (!_signup)
                TextButton(
                  onPressed: _busy ? null : _forgot,
                  child: Text(t('forgot')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
