#!/usr/bin/env python3
"""Ajusta o projeto iOS gerado pelo `flutter create` (usado na build automática):
- permissões de rede local e HTTP para o IP da impressora
- nome da app e versão mínima do iOS
"""
import pathlib
import plistlib
import re

plist_path = pathlib.Path("ios/Runner/Info.plist")
with plist_path.open("rb") as f:
    p = plistlib.load(f)

p["CFBundleDisplayName"] = "CC Remote"
p["NSLocalNetworkUsageDescription"] = (
    "Para encontrar e controlar a tua impressora Centauri Carbon na rede local.")
p["NSBonjourServices"] = p.get("NSBonjourServices", [])
ats = p.get("NSAppTransportSecurity", {})
ats["NSAllowsLocalNetworking"] = True
ats["NSAllowsArbitraryLoads"] = True  # câmara e upload por HTTP no IP da impressora
p["NSAppTransportSecurity"] = ats
p["UIFileSharingEnabled"] = True
p["LSSupportsOpeningDocumentsInPlace"] = True

with plist_path.open("wb") as f:
    plistlib.dump(p, f)
print("Info.plist ajustado")

podfile = pathlib.Path("ios/Podfile")
if podfile.exists():
    s = podfile.read_text()
    s = re.sub(r"#?\s*platform :ios, '[^']*'", "platform :ios, '13.0'", s, count=1)
    podfile.write_text(s)
    print("Podfile: iOS 13.0")

pbx = pathlib.Path("ios/Runner.xcodeproj/project.pbxproj")
s = pbx.read_text()
s = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 13.0;", s)
pbx.write_text(s)
print("Deployment target 13.0")
