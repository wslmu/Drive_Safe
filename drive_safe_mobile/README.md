# drive_safe_mobile

Flutter mobile client for Drive Safe.

## Firebase setup

This repository does not store a live Firebase Android API key.

1. Create or download your Firebase Android config from Firebase console.
2. Set android/app/google-services.json current_key to your active key.
3. Run Flutter with a compile-time define:

```powershell
flutter run --dart-define=FIREBASE_ANDROID_API_KEY=YOUR_ACTIVE_ANDROID_API_KEY
```

If you use release builds, include the same dart-define in your build command.

## Security remediation checklist

1. Rotate the leaked Google API key in Google Cloud.
2. Revoke the leaked key after rotation.
3. Review Firebase and Google Cloud access logs for suspicious use.
4. Close the GitHub secret alert only after revocation.
