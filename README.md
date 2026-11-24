# KAI BSB — die App fürs iPhone (Fassung 1)

App für Mitarbeiter der Bodensee-Schiffsbetriebe: **Asset Manager**, **Informationen** und **KI-Chat** aus KAI, dazu
**Scannen** und **Etiketten drucken** direkt mit dem iPhone. Konzept und Klick-Dummy: „KAI-App für Mitarbeiter“ (20.11.2026).

Quelle liegt im KAI-Repository unter `edge/kai-app/` und wird in das öffentliche GitHub-Repository `surfer2005/kai-app`
gespiegelt; dort baut GitHub die App auf einem Mac (gleicher Weg wie die Fahrgast-Info-App).

## Was Fassung 1 kann

- **Verbinden:** beim ersten Start die KAI-Umgebung wählen — **Test** (vorgewählt, `kai-bsb.de/test`, im Kopf „TEST“),
  **Produktion** (`kai-bsb.de`) oder **Entwicklung** (`peter.kechel.de`). Später in den Einstellungen änderbar.
- **Anmelden** auf der normalen KAI-Anmeldeseite in der App — Kennwort, zweiter Faktor und Microsoft-Anmeldung wie im
  Browser. Die App bleibt angemeldet (Speicher des iPhones, wie ein Browser).
- **Leiste unten** (Klick-Dummy „KAI-App“): links fest **Start**, dazwischen bis zu **drei Bereiche**, rechts fest **Mehr**.
  Bereiche: Dienstanweisung · Meldungen · Störmeldedienst · Asset Manager · Scannen · Informationen · Schiffstatus · KI-Chat · Bordbuch.
  Welche jemand sieht, kommt aus KAI: nach der Anmeldung liest die App die Rechte (`GET /api/auth/me`, Leserecht genügt;
  Informationen für alle, Scannen mit dem Recht Asset Manager). Vorgabe (Peter 2026-11-24): **Dienstanweisung · Meldungen ·
  Bordbuch** — fehlt jemandem das Recht für einen davon, rücken die nächsten sichtbaren Bereiche in dieser Reihenfolge nach.
  Der **Störmeldedienst** zeigt in KAI den Ablauf „Störmeldung auslösen“ in der Handy-Fassung des Klick-Dummys „Anzeiger“
  (ohne Reiter, Peter 2026-11-24); er steht unter „Mehr“ und als Kachel auf Start, nicht in der Vorgabe der Leiste. Unter **Mehr → Leiste anpassen** wählt jede Person selbst,
  welche drei unten stehen und in welcher Reihenfolge (gemerkt auf dem iPhone, „Vorgabe wiederherstellen“); fällt ein Recht weg,
  verschwindet der Bereich auch aus der Wahl. Alle übrigen Bereiche stehen unter „Mehr“ (dazu Benachrichtigungen und Mein Konto
  aus KAI, Etikett drucken, Einstellungen). Ohne Anmeldung gibt es nur „Start“ (mit der KAI-Anmeldeseite) und „Mehr“.
- **Start** zeigt die KAI-Startseite in App-Darstellung (KAI: `AppStart.vue`): Begrüßung, Glocke und Kürzel, ein Hinweis, wenn
  etwas ansteht, und die eigenen Bereiche als Kacheln (zwei nebeneinander, Zahl oben rechts: Dienstanweisung „neu“, Asset Manager
  „offline“) — ein Tipp wechselt in den Bereich; „Informationen“ öffnet die Liste Zielanzeiger … Portale. Kein Schiff, keine
  Schildchen (Peter 2026-11-24). Steht der Bereich unten in der Leiste, wechselt die Kachel auf dessen Reiter; sonst öffnet sie ihn
  im Reiter „Start“ selbst — der Zurück-Pfeil oben links führt dann zu „Start“, nicht zu „Mehr“ (Peter 2026-11-24). Was über „Mehr“
  geöffnet wird, führt wie bisher zu „Mehr“ zurück.
- In der App blendet KAI seine eigene Kopfleiste (Glocke, Konto, Uhr, Hafen …) und die Seitenleiste aus und zeigt in Listen nur
  das Suchfeld — es erkennt die App am User-Agent „KAI-BSB-App/…“ (KAI: `client/src/app-modus.js`).
- **Bordbuch** (Recht `bordbuch`, Lesen genügt) — **nur lesen** (KAI: `BordbuchLesen.vue`): öffnet mit dem Tagesüberblick (heute,
  ‹ › blättert; je Betrieb Bordbücher, Schiffe und Gäste wie in der Beförderung, dazu „Gesamt“), Tipp auf den Betrieb → seine Bordbücher als
  Kästen, Tipp → Leseseite: Kopf, Besatzung (Tipp zeigt Dienst, Arbeits- und Kontrollzeit mit Ampel), Fahrgäste als Summen, „Kurse · n“
  zugeklappt. Das Suchfeld sucht über alle Bordbücher. Erfasst wird am iPad quer oder am PC.
- **Meldungen** wie im Klick-Dummy (KAI: `MeldungenApp.vue`): „+ Meldung“, Auswahl Aktiv · Offen · In Bearbeitung · Behoben · Alle mit
  Anzahl, je Meldung ein Kasten, Tipp → lesen, „+ Meldung“ → Schiff, Anlagenteil, „Was ist los?“ (ohne Netz in der Warteschlange). Ohne
  Suchfeld, ohne Schiff als Filter, ohne die Reiter Symptomklassen/Symptome/Prioritäten. **Dienstanweisung** nur zum Lesen, ohne „Verwalten“.
  Fotos an Meldungen gibt es in KAI noch nicht.
- **Asset Manager** und **Informationen** (Zielanzeiger, GPS-Karte, Wetter, Telefonnummern, Schiffseinsatzplan,
  Dienstplan, Charter- und Cateringübersicht, Bereitschaftsplan, Portale): die KAI-Ansichten selbst, mit deinen Rechten.
  Telefonnummern lassen sich direkt anrufen.
- **KI:** der KI-Chat aus KAI (eigene KI im Haus). Das **Mikrofon** für die Spracheingabe geht auch in der App (iOS fragt
  beim ersten Mal nach), **Vorlesen** spielt die Antwort ab — auch bei stumm geschaltetem iPhone. Wer das Recht `ki_chat`
  nicht hat, sieht in KAI den Hinweis dazu.
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
Ordner `Frameworks/` oder einmal fest unter `~/Documents/Brother/` findet Xcode es selbst und bettet es signiert in die App ein (`ios/project.yml`, Schritt „Brother-Baustein
einbetten“). GitHub prüft den Druckcode gegen eine Attrappe der Schnittstellen (`ios/werkzeuge/brother-attrappe/`).

## Aufs eigene iPhone (kostenlos, über den Mac)

1. **Xcode** aus dem Mac App Store installieren (kostenlos; beim ersten Start die iOS-Plattform mitladen).
2. Bei GitHub im Repository `surfer2005/kai-app` → **Actions** → letzter grüner Lauf „iOS“ → unten den Anhang
   **KAIBSB-Xcode** herunterladen und entpacken.
3. **Brother-Baustein EINMAL auf den Mac legen:** den Ordner `BRLMPrinterKit.xcframework` (aus dem früheren Projekt,
   z. B. `Xcode/AssetManager/BRLMPrinterKit.xcframework`) nach **Dokumente → Brother** kopieren, also
   `~/Documents/Brother/BRLMPrinterKit.xcframework`. Jede neue Fassung findet ihn dort selbst — nichts mehr hineinkopieren.
   (Beim ersten Bauen fragt macOS evtl., ob Xcode auf „Dokumente“ zugreifen darf → erlauben.) Weiterhin möglich: nach
   `KAIBSB-Xcode/Frameworks/` kopieren, das geht vor. Ohne Baustein läuft die App auch, nur ohne Drucken. Im **Simulator**
   wird der Baustein nie eingebunden (dort stürzte die App mit ihm ab) — Drucken gibt es nur auf dem echten iPhone.
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
WLAN wie das iPhone; in der App unter Mehr → Einstellungen → Etikettendrucker die IP-Adresse eintragen oder „Im WLAN suchen“.

Nur im Simulator ausprobieren geht ohne Apple-ID und ohne Kabel: im Schritt 7 einen iPhone-Simulator als Ziel wählen
(keine Kamera, kein Drucker).

## Bauen auf GitHub

Bei jedem Hochladen auf `main` (`.github/workflows/ios.yml`): Druckcode gegen die Brother-Attrappe prüfen, Projekt aus
`ios/project.yml` erzeugen (XcodeGen), bauen, Prüfungen (`ios/KAIBSBTests`: Umgebungs-Adressen, Erkennen von Etiketten und
Gerätenamen, Etikett-Maße je Bandbreite, Leiste je Rechten und eigener Wahl), Bildschirmfotos im Simulator (`ios/werkzeuge/bildschirmfotos.sh`). Am Lauf
hängen **KAIBSB-Xcode** (Projekt zum Herunterladen) und **bildschirmfotos**.

Startargumente für Bildschirmfotos: `-zuruecksetzen` (Einrichtung wie beim ersten Start), `-umgebung test|produktion|entwicklung`,
`-reiter dienstanweisung|meldungen|stoermeldedienst|asset|scan|info|schiffstatus|ki|bordbuch|mehr|benachrichtigungen|konto|druck|einstellungen|leiste`
(`start-info`, `start-asset` … = Bereich im Reiter „Start“ wie nach einem Tipp auf seine Kachel),
`-rechte alle` bzw. `-rechte dienstanweisung,meldungen,…` (Reiter ohne Anmeldung vorführen; KAI-Seiten zeigen dann die Anmeldeseite),
`-vorfuehrung` (Muster-Etikett „MUSTER“, ausdrücklich als Platzhalter gekennzeichnet).

## Nächste Schritte (Konzept)

- App-Profil aus KAI (Administration → KAI-App): welche Bereiche, Rollen, Etiketten & Drucker, Geräte abmelden.
- Netzwerk-Werkzeug aus der früheren App (Bonjour, Ping, Ports, Geräteinfo).
- iPad-Ansicht (Seitenleiste, Liste + Detail), Android-App (Kotlin).
