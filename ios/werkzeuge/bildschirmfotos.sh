#!/usr/bin/env bash
# Bildschirmfotos der App im iPhone-Simulator. Die KAI-Seiten sind echt (KAI-Test, ohne Anmeldung → Anmeldeseite);
# das Etikett unter „Mehr → Etikett drucken“ ist ein deutlich gekennzeichnetes Muster (-vorfuehrung), weil ohne Anmeldung kein Gerät da ist.
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
# Ohne Anmeldung: Leiste nur „Start“ (KAI-Anmeldeseite) und „Mehr“
WARTE=15 foto 02-start-anmeldung-kai-test -umgebung test
# Leiste je Rechten (Vorführung: -rechte statt der Rechte aus KAI; die KAI-Seiten selbst zeigen ohne Anmeldung die Anmeldeseite).
# Links fest Start, dazwischen höchstens drei Bereiche, rechts fest Mehr mit den übrigen Bereichen.
WARTE=6 foto 03-mehr-schiffsfuehrer -umgebung test -rechte dienstanweisung,meldungen,bordbuch,schiffstatus -reiter mehr
WARTE=6 foto 04-mehr-it -umgebung test -rechte dienstanweisung,asset_manager,schiffstatus,ki_chat -reiter mehr
WARTE=6 foto 05-mehr-alle-rechte -umgebung test -rechte alle -reiter mehr
WARTE=6 foto 06-leiste-anpassen -umgebung test -rechte alle -reiter leiste
WARTE=15 foto 07-meldungen-kai-test -umgebung test -rechte alle -reiter meldungen
WARTE=15 foto 09-schiffstatus-unter-mehr-kai-test -umgebung test -rechte alle -reiter schiffstatus
WARTE=15 foto 10-dienstanweisung-kai-test -umgebung test -rechte dienstanweisung,meldungen,schiffstatus -reiter dienstanweisung
foto 11-informationen -umgebung test -rechte dienstanweisung,meldungen -reiter info
foto 12-scannen-unter-mehr -umgebung test -rechte alle -reiter scan
WARTE=15 foto 13-benachrichtigungen-kai-test -umgebung test -rechte alle -reiter benachrichtigungen
# Bordbuch (nur lesen), in der Vorgabe der Leiste — ohne Anmeldung zeigt die KAI-Seite die Anmeldeseite
WARTE=15 foto 18-bordbuch-kai-test -umgebung test -rechte alle -reiter bordbuch
# Kachel auf Start (Peter 2026-11-24/28): öffnet im Reiter „Start“, zurück → „Start“ (nicht „Mehr“)
foto 19-informationen-ueber-start -umgebung test -rechte dienstanweisung,meldungen,bordbuch -reiter start-info
# Kachel eines Bereichs, der AUCH unten in der Leiste steht (Peter 2026-11-28): öffnet ebenfalls im Reiter „Start“ mit „‹ Start“
WARTE=15 foto 24-dienstanweisung-ueber-start-kai-test -umgebung test -rechte dienstanweisung,meldungen,bordbuch -reiter start-da
# KI-Chat und Störmeldedienst über ihre Kachel auf Start (wie der Tipp: bereichGewaehlt → Reiter „Start“) — ohne Anmeldung zeigt KAI
# dort die Anmeldeseite; leer darf das Fenster nicht sein (Peter 2026-11-24: „Lädt …“ bzw. nichts)
WARTE=15 foto 21-ki-chat-ueber-start-kai-test -umgebung test -rechte alle -reiter start-ki
WARTE=15 foto 22-stoermeldedienst-ueber-start-kai-test -umgebung test -rechte alle -reiter start-stoer
foto 14-etikett-muster -umgebung test -rechte alle -reiter druck -vorfuehrung
WARTE=6 foto 15-einstellungen -umgebung test -reiter einstellungen
xcrun simctl ui "$UDID" appearance dark
WARTE=6 foto 16-mehr-dunkel -umgebung test -rechte alle -reiter mehr
WARTE=15 foto 17-asset-manager-dunkel -umgebung test -rechte dienstanweisung,asset_manager -reiter asset
foto 20-informationen-dunkel -umgebung test -rechte dienstanweisung,meldungen,bordbuch -reiter start-info
# große Schrift (Peter 2026-11-27: Kacheln müssen auch dann gleich groß bleiben)
xcrun simctl ui "$UDID" content_size extra-extra-large
foto 23-informationen-grosse-schrift -umgebung test -rechte dienstanweisung,meldungen,bordbuch -reiter start-info
xcrun simctl ui "$UDID" content_size large
xcrun simctl ui "$UDID" appearance light
