# KAI BSB — die App fürs iPhone (Fassung 1)

App für Mitarbeiter der Bodensee-Schiffsbetriebe: **Asset Manager** und **Informationen** aus KAI, dazu **Scannen** und
**Etiketten drucken** direkt mit dem iPhone. Konzept und Klick-Dummy: „KAI-App für Mitarbeiter“ (20.11.2026).

Quelle liegt im KAI-Repository unter `edge/kai-app/` und wird in das öffentliche GitHub-Repository `surfer2005/kai-app`
gespiegelt; dort baut GitHub die App auf einem Mac (gleicher Weg wie die Fahrgast-Info-App).

## Was Fassung 1 kann

- **Verbinden:** beim ersten Start die KAI-Umgebung wählen — **Test** (vorgewählt, `kai-bsb.de/test`, im Kopf „TEST“),
  **Produktion** (`kai-bsb.de`) oder **Entwicklung** (`peter.kechel.de`). Später in den Einstellungen änderbar.
- **Anmelden** auf der normalen KAI-Anmeldeseite in der App — Kennwort, zweiter Faktor und Microsoft-Anmeldung wie im
  Browser. Die App bleibt angemeldet (Speicher des iPhones, wie ein Browser).
- **Asset Manager** und **Informationen** (Zielanzeiger, GPS-Karte, Wetter, Telefonnummern, Schiffseinsatzplan,
  Dienstplan, Charter- und Cateringübersicht, Bereitschaftsplan, Portale): die KAI-Ansichten selbst, mit deinen Rechten.
  Telefonnummern lassen sich direkt anrufen.
- **Scannen** (Kamera, Apples Bilderkennung wie in der früheren Asset-Manager-App): QR-Etikett aus KAI
  (`…/#am_assets?asset=<Nr.>`), altes Etikett aus dem früheren Asset Manager (`bsb-betrieb.de/asset-api/app.html?asset=<alte Nr.>`,
  KAI übersetzt die Nummer) oder ein Barcode mit Gerätename/Seriennummer (z. B. „BSBPC000199“, wird im Asset Manager gesucht)
  → das Gerät öffnet sich im Reiter „Asset Manager“. Ohne Kamera (Simulator) über das Eingabefeld.
- **Drucken:** Etikett des zuletzt geöffneten Geräts — gleicher Inhalt wie in KAI (QR-Code mit dem KAI-Link, darunter der
  Name), Bandbreite 24/36 mm und Etikettenlänge wie in KAI. Drucker: **Brother PT-P710BT** (Bluetooth) oder **PT-P750W**
  (WLAN). Beide nehmen höchstens 24 mm breites Band.

**Ehrlich:** Der Druck ist ohne echten Drucker **ungetestet** — auf GitHub gibt es weder Drucker noch Brother-SDK. Der
Druckweg ist aus Peters früherer App übernommen (PT-P710BT über das gekoppelte Bluetooth-Zubehör, `com.brother.ptcbp`),
der WLAN-Weg (PT-P750W über IP-Adresse) ist neu.

## Brother-SDK (Drucker-Baustein)

Das Brother Print SDK v4 (`BRLMPrinterKit.xcframework`) liegt aus Lizenzgründen **nicht** in diesem Repository. Ohne es
baut und läuft die App, nur „Drucken“ meldet **„Drucker-Baustein fehlt“** (die Vorschau geht trotzdem). Mit dem SDK im
Ordner `Frameworks/` findet Xcode es selbst und bettet es signiert in die App ein (`ios/project.yml`, Schritt „Brother-Baustein
einbetten“). GitHub prüft den Druckcode gegen eine Attrappe der Schnittstellen (`ios/werkzeuge/brother-attrappe/`).

## Aufs eigene iPhone (kostenlos, über den Mac)

1. **Xcode** aus dem Mac App Store installieren (kostenlos; beim ersten Start die iOS-Plattform mitladen).
2. Bei GitHub im Repository `surfer2005/kai-app` → **Actions** → letzter grüner Lauf „iOS“ → unten den Anhang
   **KAIBSB-Xcode** herunterladen und entpacken.
3. **Brother-Baustein einmal hineinkopieren:** aus dem früheren Projekt den Ordner `BRLMPrinterKit.xcframework`
   (z. B. `Xcode/AssetManager/BRLMPrinterKit.xcframework`) nach `KAIBSB-Xcode/Frameworks/` kopieren.
   Ohne diesen Schritt läuft die App auch, nur ohne Drucken.
4. `KAIBSB.xcodeproj` doppelklicken. In Xcode: **Xcode → Settings → Accounts** → „+“ → eigene **Apple-ID** anmelden
   (kostenlos, kein Entwicklerprogramm nötig).
5. Links das Projekt **KAIBSB** → Ziel **KAIBSB** → Reiter **Signing & Capabilities** → bei **Team** das „Personal Team“
   wählen. Meldet Xcode, die Kennung `de.kaibsb.kaiapp` sei nicht verfügbar: **Bundle Identifier** ändern, z. B. in
   `de.kaibsb.kaiapp.peter`.
6. **iPhone per Kabel** an den Mac, am iPhone „Diesem Computer vertrauen“. Am iPhone den **Entwicklermodus** einschalten:
   Einstellungen → Datenschutz & Sicherheit → Entwicklermodus → an (das iPhone startet neu).
7. In Xcode oben das **iPhone als Ziel** wählen und **▶** drücken. Beim ersten Mal am iPhone: Einstellungen → Allgemein →
   VPN & Geräteverwaltung → die eigene Apple-ID → **Vertrauen**. Dann die App „KAI BSB“ öffnen.
8. Die App **läuft 7 Tage**, danach in Xcode einfach wieder ▶ (iPhone am Kabel).

Drucker vorbereiten: **PT-P710BT** einmal in den iPhone-Einstellungen unter **Bluetooth** koppeln. **PT-P750W**: im selben
WLAN wie das iPhone; in der App unter Einstellungen → Etikettendrucker die IP-Adresse eintragen oder „Im WLAN suchen“.

Nur im Simulator ausprobieren geht ohne Apple-ID und ohne Kabel: im Schritt 7 einen iPhone-Simulator als Ziel wählen
(keine Kamera, kein Drucker).

## Bauen auf GitHub

Bei jedem Hochladen auf `main` (`.github/workflows/ios.yml`): Druckcode gegen die Brother-Attrappe prüfen, Projekt aus
`ios/project.yml` erzeugen (XcodeGen), bauen, Prüfungen (`ios/KAIBSBTests`: Umgebungs-Adressen, Erkennen von Etiketten und
Gerätenamen, Etikett-Maße je Bandbreite), Bildschirmfotos im Simulator (`ios/werkzeuge/bildschirmfotos.sh`). Am Lauf
hängen **KAIBSB-Xcode** (Projekt zum Herunterladen) und **bildschirmfotos**.

Startargumente für Bildschirmfotos: `-zuruecksetzen` (Einrichtung wie beim ersten Start), `-umgebung test|produktion|entwicklung`,
`-reiter asset|info|scan|druck|einstellungen`, `-vorfuehrung` (Muster-Etikett „MUSTER“, ausdrücklich als Platzhalter gekennzeichnet).

## Nächste Schritte (Konzept)

- App-Profil aus KAI (Administration → KAI-App): welche Bereiche, Rollen, Etiketten & Drucker, Geräte abmelden.
- Netzwerk-Werkzeug aus der früheren App (Bonjour, Ping, Ports, Geräteinfo).
- iPad-Ansicht (Seitenleiste, Liste + Detail), Android-App (Kotlin).
