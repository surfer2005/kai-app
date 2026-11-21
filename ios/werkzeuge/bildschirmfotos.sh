#!/usr/bin/env bash
# Bildschirmfotos der App im iPhone-Simulator. Die KAI-Seiten sind echt (KAI-Test, ohne Anmeldung → Anmeldeseite);
# das Etikett im Reiter „Drucken“ ist ein deutlich gekennzeichnetes Muster (-vorfuehrung), weil ohne Anmeldung kein Gerät da ist.
#   bildschirmfotos.sh <Simulator-UDID> <Pfad zur .app> <Zielordner>
set -euo pipefail
UDID=$1; APP=$2; ZIEL=$3; ID=de.kaibsb.kaiapp
mkdir -p "$ZIEL"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 10:14 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" "$APP"
foto() {
  local name=$1; shift
  xcrun simctl terminate "$UDID" "$ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$ID" -AppleLanguages "(de)" -AppleLocale de_DE "$@" >/dev/null
  sleep "${WARTE:-5}"
  xcrun simctl io "$UDID" screenshot "$ZIEL/$name.png" >/dev/null
  echo "✔ $name"
}
xcrun simctl ui "$UDID" appearance light
foto 01-erster-start -zuruecksetzen
WARTE=15 foto 02-asset-manager-kai-test -umgebung test -reiter asset
foto 03-informationen -umgebung test -reiter info
foto 04-scannen -umgebung test -reiter scan
foto 05-drucken-muster -umgebung test -reiter druck -vorfuehrung
WARTE=6 foto 06-einstellungen -umgebung test -reiter einstellungen
xcrun simctl ui "$UDID" appearance dark
foto 07-informationen-dunkel -umgebung test -reiter info
WARTE=15 foto 08-asset-manager-dunkel -umgebung test -reiter asset
xcrun simctl ui "$UDID" appearance light
