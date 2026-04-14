import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_screen.dart';
import 'firebase_bootstrap.dart';
import 'monitoring_screen.dart';
import 'profile_screen.dart';
import 'session_detail_screen.dart';
import 'session_history.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.initialize();
  runApp(const DriveSafeMobileApp());
}

class DriveSafeMobileApp extends StatelessWidget {
  const DriveSafeMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF08111D);
    const surface = Color(0xFF111E2D);
    const text = Color(0xFFF2F6FB);
    const accent = Color(0xFF52A8FF);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Drive Safe',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: Color(0xFF4FE0D0),
          surface: surface,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: text,
            letterSpacing: -0.8,
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: text,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: text,
          ),
          bodyLarge: TextStyle(
            fontSize: 15,
            color: text,
            height: 1.4,
          ),
          bodyMedium: TextStyle(
            fontSize: 13,
            color: Color(0xFF8FA2B7),
            height: 1.4,
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (!FirebaseBootstrap.isEnabled) {
      return const MobileShell();
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          FirebaseAuth.instance.signInAnonymously();
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return const MobileShell();
      },
    );
  }
}

class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    const navBg = Color(0xFF0D1826);
    const selected = Color(0xFF52A8FF);
    const unselected = Color(0xFF7D92A9);

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(
            key: ValueKey(_index),
            child: [
              HomeScreen(
                onStartMonitoring: () => setState(() => _index = 1),
              ),
              const MonitoringScreen(),
              const HistoryScreen(),
              const ProfileScreen(),
            ][_index],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: navBg,
          indicatorColor: selected.withValues(alpha: 0.18),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? selected : unselected,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected) ? Colors.white : unselected,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Accueil'),
            NavigationDestination(icon: Icon(Icons.visibility_rounded), label: 'Surveillance'),
            NavigationDestination(icon: Icon(Icons.insights_rounded), label: 'Historique'),
            NavigationDestination(icon: Icon(Icons.person_outline_rounded), label: 'Profil'),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final VoidCallback onStartMonitoring;

  const HomeScreen({
    super.key,
    required this.onStartMonitoring,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TopBar(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: const LinearGradient(
                colors: [Color(0xFF17304D), Color(0xFF0F1D2D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0xFF294764)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF56E0D2).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Edge AI  |  Prevention temps reel',
                    style: TextStyle(
                      color: Color(0xFF56E0D2),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Drive Safe', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 10),
                Text(
                  'Version mobile Android du projet, avec surveillance locale de la vigilance du conducteur et design privacy-first.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onStartMonitoring,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Demarrer la session'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF52A8FF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Parcours de demarrage'),
          const SizedBox(height: 14),
          const _ChecklistTile(
            icon: Icons.smartphone_rounded,
            title: 'Fixer le smartphone sur un support stable',
            subtitle: 'La camera frontale doit rester orientee vers le conducteur.',
          ),
          const SizedBox(height: 12),
          const _ChecklistTile(
            icon: Icons.face_retouching_natural_rounded,
            title: 'Calibration du visage au debut de session',
            subtitle: 'Le systeme apprend une posture normale avant d evaluer la fatigue.',
          ),
          const SizedBox(height: 12),
          const _ChecklistTile(
            icon: Icons.warning_amber_rounded,
            title: 'Alerte locale si somnolence critique detectee',
            subtitle: 'Le score de vigilance baisse en fonction des signes faciaux observes.',
          ),
        ],
      ),
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final canAccessHistory = user != null;

    if (!canAccessHistory) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          const _TopBar(),
          const SizedBox(height: 20),
          const SectionTitle('Historique des sessions'),
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
                  'Connectez-vous pour consulter votre historique cloud detaille.',
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
        ],
      );
    }

    return FutureBuilder<List<SessionRecord>>(
      future: SessionHistoryStore.loadSessions(),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const <SessionRecord>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            const _TopBar(),
            const SizedBox(height: 20),
            const SectionTitle('Historique des sessions'),
            const SizedBox(height: 14),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (sessions.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF111E2D),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF243C55)),
                ),
                child: const Text(
                  'Aucune session enregistree pour le moment. Terminez une surveillance pour alimenter cet historique.',
                  style: TextStyle(color: Color(0xFF8FA2B7), height: 1.5),
                ),
              )
            else
              ...sessions.map(
                (session) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SessionCard(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SessionDetailScreen(session: session),
                        ),
                      );
                    },
                    date: _formatSessionDate(session.startedAtIso),
                    duration: _formatDuration(session.durationSeconds),
                    score: '${100 - session.averageFatigueScore}%',
                    alerts: '${session.alertCount} alerte(s)',
                    state: session.dominantState,
                    accent: _accentFromScore(session.maxFatigueScore),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatSessionDate(String startedAtIso) {
    final date = DateTime.tryParse(startedAtIso)?.toLocal();
    if (date == null) return 'Session recente';
    const months = ['janv', 'fevr', 'mars', 'avr', 'mai', 'juin', 'juil', 'aout', 'sept', 'oct', 'nov', 'dec'];
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]}  $hh:$mm';
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remMinutes = minutes % 60;
      return '${hours}h ${remMinutes.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Color _accentFromScore(int fatigueScore) {
    if (fatigueScore >= 60) return const Color(0xFFFF6B78);
    if (fatigueScore >= 30) return const Color(0xFFF0B24D);
    return const Color(0xFF42C983);
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: const [
        _TopBar(),
        SizedBox(height: 20),
        SectionTitle('Confidentialite et conformite'),
        SizedBox(height: 14),
        _PrivacyTile(
          icon: Icons.memory_rounded,
          title: 'Traitement local sur l appareil',
          subtitle: 'Les calculs sont effectues sur le telephone sans serveur externe.',
        ),
        SizedBox(height: 12),
        _PrivacyTile(
          icon: Icons.videocam_off_rounded,
          title: 'Aucune video enregistree',
          subtitle: 'Le flux camera est analyse a la volee et non archive.',
        ),
        SizedBox(height: 12),
        _PrivacyTile(
          icon: Icons.fingerprint_rounded,
          title: 'Aucune biometrie stockee',
          subtitle: 'Le systeme ne garde ni empreinte faciale ni identifiant personnel.',
        ),
      ],
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
          child: const Icon(Icons.shield_moon_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Drive Safe', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text('Prototype mobile Android', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;

  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.headlineMedium);
  }
}

class _ChecklistTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ChecklistTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111E2D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF243C55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF52A8FF).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF52A8FF)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8FA2B7),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final VoidCallback onTap;
  final String date;
  final String duration;
  final String score;
  final String alerts;
  final String state;
  final Color accent;

  const _SessionCard({
    required this.onTap,
    required this.date,
    required this.duration,
    required this.score,
    required this.alerts,
    required this.state,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF111E2D),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF243C55)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(date, style: const TextStyle(color: Color(0xFF8FA2B7), fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    state,
                    style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
                Text(score, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
              ],
            ),
            const SizedBox(height: 12),
            Text('$duration  |  $alerts', style: const TextStyle(color: Color(0xFF8FA2B7), height: 1.4)),
            const SizedBox(height: 8),
            const Text('Appuyez pour voir les details', style: TextStyle(color: Color(0xFF52A8FF), fontSize: 12)),
          ],
        ),
      ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111E2D),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF243C55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF56E0D2).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF56E0D2)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(color: Color(0xFF8FA2B7), height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
