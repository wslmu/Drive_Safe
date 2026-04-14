import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_bootstrap.dart';

class ProfileData {
  final String fullName;
  final String phone;

  const ProfileData({
    required this.fullName,
    required this.phone,
  });

  Map<String, dynamic> toJson() {
    return {
      'fullName': fullName,
      'phone': phone,
    };
  }

  factory ProfileData.fromJson(Map<String, dynamic> json) {
    return ProfileData(
      fullName: json['fullName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
    );
  }
}

class ProfileStore {
  static Future<ProfileData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final localName = prefs.getString('profile_fullName') ?? '';
    final localPhone = prefs.getString('profile_phone') ?? '';

    var data = ProfileData(
      fullName: localName,
      phone: localPhone,
    );

    if (!FirebaseBootstrap.isEnabled) {
      return data;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return data;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('meta')
          .doc('profile')
          .get();
      final remote = doc.data();
      if (remote != null) {
        data = ProfileData.fromJson(remote);
      }
    } catch (_) {
      // Keep local profile as fallback.
    }

    return data;
  }

  static Future<void> save(ProfileData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_fullName', data.fullName);
    await prefs.setString('profile_phone', data.phone);

    if (!FirebaseBootstrap.isEnabled) {
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('meta')
          .doc('profile')
          .set(data.toJson(), SetOptions(merge: true));
    } catch (_) {
      // Local profile already saved.
    }
  }
}
