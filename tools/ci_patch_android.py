#!/usr/bin/env python3
"""Ajusta o projeto Android gerado pelo `flutter create` (usado na build automática):
- minSdk 26 (exigido pelo tflite_flutter)
- core library desugaring (exigido pelo flutter_local_notifications)
- permissões de rede, notificações e tráfego HTTP local
"""
import pathlib
import re

app = pathlib.Path("android/app")
kts = app / "build.gradle.kts"
groovy = app / "build.gradle"

if kts.exists():
    s = kts.read_text()
    s = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 26", s)
    if "isCoreLibraryDesugaringEnabled" not in s:
        s = s.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    if "desugar_jdk_libs" not in s:
        s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    kts.write_text(s)
    print("build.gradle.kts ajustado")
elif groovy.exists():
    s = groovy.read_text()
    s = re.sub(r"minSdk(Version)?\s*=?\s*[^\n]+", "minSdkVersion 26", s, count=1)
    if "coreLibraryDesugaringEnabled" not in s:
        s = s.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
    if "desugar_jdk_libs" not in s:
        s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    groovy.write_text(s)
    print("build.gradle ajustado")
else:
    raise SystemExit("build.gradle não encontrado")

manifest = app / "src/main/AndroidManifest.xml"
m = manifest.read_text()
perms = ["INTERNET", "ACCESS_WIFI_STATE", "CHANGE_WIFI_MULTICAST_STATE", "POST_NOTIFICATIONS", "WAKE_LOCK"]
add = "".join(f'    <uses-permission android:name="android.permission.{p}"/>\n'
              for p in perms if f"android.permission.{p}" not in m)
if add:
    m = m.replace("<application", add + "    <application", 1)
if "usesCleartextTraffic" not in m:
    m = m.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="CC Remote"', m, count=1)
manifest.write_text(m)
print("AndroidManifest.xml ajustado")

# Alguns plugins (ex.: tflite_flutter) compilam Java para 1.8 e Kotlin para 17;
# o Gradle atual trata essa diferença como erro. Passa a ser só aviso.
props = pathlib.Path("android/gradle.properties")
p = props.read_text() if props.exists() else ""
if "kotlin.jvm.target.validation.mode" not in p:
    props.write_text(p.rstrip("\n") + "\nkotlin.jvm.target.validation.mode=warning\n")
    print("gradle.properties ajustado")
