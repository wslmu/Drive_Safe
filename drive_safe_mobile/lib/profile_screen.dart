import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_screen.dart';
import 'profile_store.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    final profile = await ProfileStore.load();
    if (!mounted) return;
    setState(() {
      _nameController.text = profile.fullName.isNotEmpty
          ? profile.fullName
          : (user?.displayName ?? '');
      _phoneController.text = profile.phone;
    });
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    setState(() => _saving = true);

    final data = ProfileData(
      fullName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
    );

    try {
      await ProfileStore.save(data);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updateDisplayName(data.fullName);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil enregistre.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email utilisateur indisponible.')),
      );
      return;
    }

    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email de reinitialisation envoye a $email')),
      );
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.isAnonymous) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          const _TopBar(),
          const SizedBox(height: 20),
          const Text(
            'Profil',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF111E2D),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF243C55)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connectez-vous ou inscrivez-vous pour gerer votre profil et synchroniser vos sessions.',
                  style: TextStyle(color: Color(0xFF8FA2B7), height: 1.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AuthScreen(signupMode: false),
                            ),
                          );
                        },
                        child: const Text('Se connecter'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AuthScreen(signupMode: true),
                            ),
                          );
                        },
                        child: const Text('S inscrire'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _PrivacySection(),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const _TopBar(),
        const SizedBox(height: 20),
        const Text(
          'Profil',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 26),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF111E2D),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF243C55)),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: const Color(0xFF1C334B),
                child: const Icon(Icons.person, color: Color(0xFF8FA2B7), size: 38),
              ),
              const SizedBox(height: 12),
              Text(
                user.email ?? 'Email non disponible',
                style: const TextStyle(color: Color(0xFF8FA2B7)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InputField(label: 'Nom complet', controller: _nameController),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111E2D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2C4A66)),
          ),
          child: Text(
            'Email: ${user.email ?? 'non disponible'}',
            style: const TextStyle(color: Color(0xFF8FA2B7)),
          ),
        ),
        const SizedBox(height: 10),
        _InputField(label: 'Telephone', controller: _phoneController),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _saving ? null : _saveProfile,
          child: Text(_saving ? 'Enregistrement...' : 'Enregistrer profil'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _sendPasswordReset,
          child: const Text('Changer mot de passe (email reset)'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _signOut,
          child: const Text('Se deconnecter'),
        ),
        const SizedBox(height: 20),
        const _PrivacySection(),
      ],
    );
  }
}

class _InputField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _InputField({
    required this.label,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8FA2B7)),
        filled: true,
        fillColor: const Color(0xFF111E2D),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF56E0D2), Color(0xFF52A8FF)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.person_outline_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Compte utilisateur', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
              SizedBox(height: 2),
              Text('Gerer vos informations et votre securite', style: TextStyle(color: Color(0xFF8FA2B7))),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Confidentialite',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
        SizedBox(height: 10),
        _PrivacyTile(
          icon: Icons.memory_rounded,
          title: 'Traitement local sur l appareil',
          subtitle: 'Les calculs sont effectues sur le telephone sans serveur externe.',
        ),
        SizedBox(height: 10),
        _PrivacyTile(
          icon: Icons.videocam_off_rounded,
          title: 'Aucune video enregistree',
          subtitle: 'Le flux camera est analyse a la volee et non archive.',
        ),
        SizedBox(height: 10),
        _PrivacyTile(
          icon: Icons.fingerprint_rounded,
          title: 'Aucune biometrie stockee',
          subtitle: 'Le systeme ne garde ni empreinte faciale ni identifiant personnel.',
        ),
      ],
    );
  }
}

class _PrivacyTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PrivacyTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111E2D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF243C55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF56E0D2)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF8FA2B7), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
