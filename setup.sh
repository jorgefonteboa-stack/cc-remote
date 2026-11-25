#!/usr/bin/env bash
# Gera as pastas android/ e ios/ e aplica as permissões de rede necessárias.
# Correr uma vez, na raiz do projeto: ./setup.sh   (macOS ou Linux; iOS só em macOS)
set -euo pipefail

flutter create --platforms=android,ios --org com.ccremote --project-name cc_remote .
flutter pub get

# ---------- Android ----------
MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q CHANGE_WIFI_MULTICAST_STATE "$MANIFEST"; then
  perl -0pi -e 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>\n    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <uses-permission android:name="android.permission.WAKE_LOCK"/>\n    <application android:usesCleartextTraffic="true"|' "$MANIFEST"
  echo "Android: permissões e cleartext adicionados."
fi

# flutter_local_notifications precisa de core library desugaring no Android
GRADLE=android/app/build.gradle.kts
[[ -f "$GRADLE" ]] || GRADLE=android/app/build.gradle
if [[ -f "$GRADLE" ]] && ! grep -q desugar "$GRADLE"; then
  echo "AVISO: ativa coreLibraryDesugaring em $GRADLE (ver README, secção Vigilância IA)."
fi

# ---------- iOS ----------
PLIST=ios/Runner/Info.plist
if [[ "$(uname)" == "Darwin" ]] && [[ -f "$PLIST" ]]; then
  /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string 'Para encontrar e controlar a tua impressora Centauri Carbon na rede local.'" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :NSBonjourServices array" "$PLIST" 2>/dev/null || true
  # flutter_inappwebview exige iOS 12+
  sed -i '' "s/# platform :ios, '.*'/platform :ios, '13.0'/" ios/Podfile 2>/dev/null || true
  echo "iOS: Info.plist atualizado."
fi

echo "Pronto. Liga o telemóvel e corre: flutter run"
