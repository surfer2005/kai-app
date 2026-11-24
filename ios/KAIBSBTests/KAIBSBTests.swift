import XCTest
@testable import KAIBSB

final class UmgebungTests: XCTestCase {
    func testAdressen() {
        XCTAssertEqual(Umgebung.test.adresse, "https://kai-bsb.de/test")
        XCTAssertEqual(Umgebung.produktion.adresse, "https://kai-bsb.de")
        XCTAssertEqual(Umgebung.entwicklung.adresse, "https://peter.kechel.de")
        XCTAssertEqual(Umgebung.test.startseite.absoluteString, "https://kai-bsb.de/test/")
        XCTAssertEqual(Umgebung.produktion.startseite.absoluteString, "https://kai-bsb.de/")
    }

    func testNurTestUndEntwicklungTragenEinKennzeichen() {
        XCTAssertEqual(Umgebung.test.kennzeichen, "TEST")
        XCTAssertNil(Umgebung.produktion.kennzeichen)
        XCTAssertNotNil(Umgebung.entwicklung.kennzeichen)
    }

    func testAnsichtenUndApi() {
        XCTAssertEqual(Umgebung.test.ansicht("am_assets_neu").absoluteString, "https://kai-bsb.de/test/#am_assets_neu")
        XCTAssertEqual(Umgebung.produktion.ansicht("zielanzeiger").absoluteString, "https://kai-bsb.de/#zielanzeiger")
        XCTAssertEqual(Umgebung.test.api("asset-manager/assets/12").absoluteString, "https://kai-bsb.de/test/api/asset-manager/assets/12")
        XCTAssertEqual(Umgebung.entwicklung.api("go/asset/10148").absoluteString, "https://peter.kechel.de/api/go/asset/10148")
    }

    /// Wie KAI das Etikett druckt: origin + BASE_URL + #am_assets?asset=<id> (AssetManagerView, assetDeepLink).
    func testGeraeteLinkWieInKai() {
        XCTAssertEqual(Umgebung.test.geraeteLink(2760), "https://kai-bsb.de/test/#am_assets?asset=2760")
        XCTAssertEqual(Umgebung.produktion.geraeteLink(2760), "https://kai-bsb.de/#am_assets?asset=2760")
    }

    func testUmgebungEinerAdresse() throws {
        XCTAssertEqual(Umgebung.zu(url: try XCTUnwrap(URL(string: "https://kai-bsb.de/test/#am_assets"))), .test)
        XCTAssertEqual(Umgebung.zu(url: try XCTUnwrap(URL(string: "https://kai-bsb.de/test"))), .test)
        XCTAssertEqual(Umgebung.zu(url: try XCTUnwrap(URL(string: "https://kai-bsb.de/#home"))), .produktion)
        XCTAssertEqual(Umgebung.zu(url: try XCTUnwrap(URL(string: "https://kai-bsb.de/testlauf"))), .produktion)
        XCTAssertEqual(Umgebung.zu(url: try XCTUnwrap(URL(string: "https://peter.kechel.de/#am_assets_neu"))), .entwicklung)
        XCTAssertNil(Umgebung.zu(url: try XCTUnwrap(URL(string: "https://bsb-betrieb.de/asset-api/app.html"))))
        XCTAssertTrue(Umgebung.test.enthaelt(URL(string: "https://kai-bsb.de/test/?app=1#am_assets_neu")))
        XCTAssertFalse(Umgebung.produktion.enthaelt(URL(string: "https://kai-bsb.de/test/")))
    }
}

final class ReiterTests: XCTestCase {
    /// Startargument `-reiter …`: Bereiche bzw. Seiten unter „Mehr“ (Drucken, Einstellungen, Leiste anpassen …).
    func testStartargumente() {
        XCTAssertEqual(StartZiel.aus("ki"), .bereich(.kiChat))
        XCTAssertEqual(StartZiel.aus("asset"), .bereich(.assetManager))
        XCTAssertEqual(StartZiel.aus("meldungen"), .bereich(.meldungen))
        XCTAssertEqual(StartZiel.aus("dienstanweisung"), .bereich(.dienstanweisung))
        XCTAssertEqual(StartZiel.aus("schiffstatus"), .bereich(.schiffstatus))
        XCTAssertEqual(StartZiel.aus("bordbuch"), .bereich(.bordbuch))
        XCTAssertEqual(StartZiel.aus("stoermeldedienst"), .bereich(.stoermeldedienst))
        XCTAssertEqual(StartZiel.aus("start-stoer"), .start([.stoermeldedienst]))
        XCTAssertEqual(StartZiel.aus("druck"), .mehr([.drucken]))
        XCTAssertEqual(StartZiel.aus("einstellungen"), .mehr([.einstellungen]))
        XCTAssertEqual(StartZiel.aus("benachrichtigungen"), .mehr([.benachrichtigungen]))
        XCTAssertEqual(StartZiel.aus("konto"), .mehr([.konto]))
        XCTAssertEqual(StartZiel.aus("leiste"), .mehr([.leiste]))
        XCTAssertNil(StartZiel.aus("start"))   // Start ist ohnehin der erste Reiter
        XCTAssertNil(StartZiel.aus("unbekannt"))
        // Bereich im Reiter „Start“ (wie nach einem Tipp auf die Kachel)
        XCTAssertEqual(StartZiel.aus("start-info"), .start([.informationen]))
        XCTAssertEqual(StartZiel.aus("start-asset"), .start([.assetManager]))
        XCTAssertNil(StartZiel.aus("start-mehr"))
        XCTAssertNil(StartZiel.aus("start-unbekannt"))
    }

    /// Peter 2026-11-24: Informationen → Zielanzeiger → zurück → zurück führte zu „Mehr“ statt zu „Start“. Eine Kachel auf Start,
    /// deren Bereich nicht unten steht, öffnet ihn in der Navigation des Reiters „Start“; „Mehr“ bleibt unberührt.
    func testKachelOhneReiterUntenBleibtImStart() {
        let unten: [Bereich] = [.dienstanweisung, .meldungen, .bordbuch]
        let vorher = Weg(reiter: .start, startPfad: [], mehrPfad: [.bereich(.schiffstatus)])
        for b in [Bereich.informationen, .stoermeldedienst, .assetManager, .scannen, .schiffstatus, .kiChat] {
            let weg = vorher.kachel(b, unten: unten)
            XCTAssertEqual(weg.reiter, .start, "\(b)")
            XCTAssertEqual(weg.startPfad, [b], "\(b)")
            XCTAssertEqual(weg.mehrPfad, [.bereich(.schiffstatus)], "Mehr bleibt unberührt (\(b))")
        }
        // ein zweiter Tipp ersetzt den Weg, er stapelt nicht
        XCTAssertEqual(vorher.kachel(.informationen, unten: unten).kachel(.kiChat, unten: unten).startPfad, [.kiChat])
    }

    /// Steht der Bereich unten, wechselt die Kachel wie bisher auf seinen Reiter — beide Wege bleiben, wie sie sind.
    func testKachelMitReiterUntenWechseltDorthin() {
        let unten: [Bereich] = [.dienstanweisung, .meldungen, .bordbuch]
        let vorher = Weg(reiter: .start, startPfad: [.informationen], mehrPfad: [.einstellungen])
        for b in unten {
            let weg = vorher.kachel(b, unten: unten)
            XCTAssertEqual(weg.reiter, .bereich(b))
            XCTAssertEqual(weg.startPfad, [.informationen])
            XCTAssertEqual(weg.mehrPfad, [.einstellungen])
        }
        // ohne bekannte Rechte steht unten nichts: auch dann im Reiter „Start“, nie unter „Mehr“
        XCTAssertEqual(Weg().kachel(.meldungen, unten: []), Weg(reiter: .start, startPfad: [.meldungen], mehrPfad: []))
    }

    /// Die Bereiche tragen die Namen, Rechte und Ansichten aus KAI (client/src/app-modus.js, APP_BEREICHE).
    func testBereicheWieInKai() {
        // Störmeldedienst wieder in der App (Peter 2026-11-24: Ansicht nach dem Klick-Dummy „Anzeiger“ gebaut)
        XCTAssertEqual(Bereich.allCases.map(\.rawValue), ["dienstanweisung", "meldungen", "stoermeldedienst", "asset_manager", "scannen", "informationen", "schiffstatus", "ki_chat", "bordbuch"])
        XCTAssertEqual(Bereich.stoermeldedienst.recht, "stoermeldedienst")
        XCTAssertEqual(Bereich.stoermeldedienst.kaiAnsicht, "stoermeldedienst")
        XCTAssertEqual(Bereich.stoermeldedienst.name, "Störmeldedienst")
        XCTAssertEqual(Bereich.assetManager.kaiAnsicht, "am_assets_neu")
        XCTAssertNil(Bereich.scannen.kaiAnsicht)
        XCTAssertEqual(Bereich.scannen.recht, "asset_manager")
        XCTAssertNil(Bereich.informationen.recht)
        XCTAssertEqual(Bereich.assetManager.leistenName, "Assets")
        // Bordbuch zum Lesen (Peter 2026-11-23): Recht und KAI-Ansicht „bordbuch“
        XCTAssertEqual(Bereich.bordbuch.recht, "bordbuch")
        XCTAssertEqual(Bereich.bordbuch.kaiAnsicht, "bordbuch")
        XCTAssertEqual(Bereich.bordbuch.name, "Bordbuch")
    }

    /// So liefert KAI /api/auth/me (Ausschnitt) — nur die Texteinträge zählen.
    func testRechteAusAuthMe() throws {
        let json = #"{"id":2,"name":"Peter Bode","role":"admin","permissions":{"meldungen":"write","schiffstatus":"read","ki_chat":"none"}}"#
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(KaiApi.rechteAus(obj), ["meldungen": "write", "schiffstatus": "read", "ki_chat": "none"])
        XCTAssertEqual(KaiApi.rechteAus(["permissions": ["x": 1]]), [:])
        XCTAssertEqual(KaiApi.rechteAus([:]), [:])
    }
}

/// Welche Bereiche unten zwischen „Start“ und „Mehr“ stehen (höchstens drei) und welche unter „Mehr“ — je Rechten und eigener Wahl.
final class LeisteTests: XCTestCase {
    private func lesen(_ schluessel: String...) -> [String: String] {
        Dictionary(uniqueKeysWithValues: schluessel.map { ($0, "read") })
    }
    private let alle = Dictionary(uniqueKeysWithValues: ["dienstanweisung", "meldungen", "asset_manager", "schiffstatus", "ki_chat", "bordbuch"].map { ($0, "write") })

    func testHoechstensDrei() {
        XCTAssertEqual(Leiste.hoechstens, 3)
    }

    /// Nur mit Leserecht (read oder write); „none“ und fehlende Rechte zählen nicht. Informationen sieht jeder.
    func testNurMitLeserecht() {
        let l = Leiste.berechnen(rechte: ["dienstanweisung": "read", "meldungen": "none", "schiffstatus": "write"], wahl: nil)
        XCTAssertEqual(l.unten, [.dienstanweisung, .informationen, .schiffstatus])
        XCTAssertEqual(l.mehr, [])
        XCTAssertEqual(Leiste.berechnen(rechte: [:], wahl: nil).unten, [.informationen])
    }

    /// Schiffsführer (Rechte wie im Dummy): Dienstanweisung, Meldungen, Bordbuch unten, Informationen und Schiffstatus unter „Mehr“.
    func testVorgabeSchiffsfuehrer() {
        let l = Leiste.berechnen(rechte: lesen("dienstanweisung", "meldungen", "bordbuch", "schiffstatus"), wahl: nil)
        XCTAssertEqual(l.unten, [.dienstanweisung, .meldungen, .bordbuch])
        XCTAssertEqual(l.mehr, [.informationen, .schiffstatus])
    }

    /// Vorgabe (Peter 2026-11-24): Dienstanweisung · Meldungen · Bordbuch in dieser Reihenfolge; ohne Recht `bordbuch` fehlt das
    /// Bordbuch ganz.
    func testVorgabeDienstanweisungMeldungenBordbuch() {
        XCTAssertEqual(Leiste.vorgabeReihenfolge, [.dienstanweisung, .meldungen, .bordbuch])
        XCTAssertEqual(Leiste.vorgabe(alle), [.dienstanweisung, .meldungen, .bordbuch])
        let l = Leiste.berechnen(rechte: alle, wahl: nil)
        XCTAssertEqual(l.unten, [.dienstanweisung, .meldungen, .bordbuch])
        XCTAssertEqual(l.mehr, [.assetManager, .scannen, .informationen, .schiffstatus, .kiChat])
        let nurBordbuch = Leiste.berechnen(rechte: lesen("bordbuch"), wahl: nil)
        XCTAssertEqual(nurBordbuch.unten, [.bordbuch, .informationen])
        XCTAssertEqual(nurBordbuch.mehr, [])
        XCTAssertFalse(Leiste.berechnen(rechte: lesen("dienstanweisung"), wahl: [.bordbuch]).mehr.contains(.bordbuch))
    }

    /// Fehlt ein Recht der Vorgabe, rücken die nächsten sichtbaren Bereiche in der festen Reihenfolge nach.
    func testVorgabeRueckenNach() {
        let ohneMeldungen = Leiste.berechnen(rechte: lesen("dienstanweisung", "bordbuch", "asset_manager"), wahl: nil)
        XCTAssertEqual(ohneMeldungen.unten, [.dienstanweisung, .bordbuch, .assetManager])
        XCTAssertEqual(ohneMeldungen.mehr, [.scannen, .informationen])
        // IT ohne Meldungen und Bordbuch: Dienstanweisung, Assets, Scannen
        let it = Leiste.berechnen(rechte: lesen("dienstanweisung", "asset_manager", "schiffstatus", "ki_chat"), wahl: nil)
        XCTAssertEqual(it.unten, [.dienstanweisung, .assetManager, .scannen])
        XCTAssertEqual(it.mehr, [.informationen, .schiffstatus, .kiChat])
    }

    /// Eigene Wahl gilt in ihrer Reihenfolge — auch der Asset Manager, wenn ihn jemand ausdrücklich gewählt hat.
    func testGespeicherteWahl() {
        let l = Leiste.berechnen(rechte: alle, wahl: [.schiffstatus, .assetManager, .kiChat])
        XCTAssertEqual(l.unten, [.schiffstatus, .assetManager, .kiChat])
        XCTAssertEqual(l.mehr, [.dienstanweisung, .meldungen, .scannen, .informationen, .bordbuch])
    }

    /// Mehr als drei oder doppelt Gespeichertes wird gekürzt.
    func testWahlHoechstensDreiOhneDoppelte() {
        let l = Leiste.berechnen(rechte: alle, wahl: [.kiChat, .kiChat, .meldungen, .informationen, .scannen])
        XCTAssertEqual(l.unten, [.kiChat, .meldungen, .informationen])
        XCTAssertTrue(l.mehr.contains(.scannen))
    }

    /// Fällt ein Recht weg, verschwindet der Bereich auch aus der gespeicherten Wahl.
    func testRechtWegAusWahl() {
        let l = Leiste.berechnen(rechte: lesen("dienstanweisung"), wahl: [.assetManager, .dienstanweisung, .kiChat])
        XCTAssertEqual(l.unten, [.dienstanweisung])
        XCTAssertEqual(l.mehr, [.informationen])
    }

    /// Bleibt von einer Wahl nichts übrig (alle Rechte weg), gilt die Vorgabe; eine bewusst leere Wahl bleibt leer.
    func testWahlLeer() {
        XCTAssertEqual(Leiste.berechnen(rechte: lesen("meldungen"), wahl: [.assetManager]).unten, [.meldungen, .informationen])
        let leer = Leiste.berechnen(rechte: lesen("meldungen"), wahl: [])
        XCTAssertEqual(leer.unten, [])
        XCTAssertEqual(leer.mehr, [.meldungen, .informationen])
    }

    func testAnpassen() {
        var unten: [Bereich] = [.dienstanweisung, .meldungen]
        unten = Leiste.hinzufuegen(.schiffstatus, zu: unten)
        XCTAssertEqual(unten, [.dienstanweisung, .meldungen, .schiffstatus])
        XCTAssertEqual(Leiste.hinzufuegen(.kiChat, zu: unten), unten)                  // voll
        XCTAssertEqual(Leiste.hinzufuegen(.meldungen, zu: [.meldungen]), [.meldungen]) // schon da
        XCTAssertEqual(Leiste.verschieben(.schiffstatus, um: -1, in: unten), [.dienstanweisung, .schiffstatus, .meldungen])
        XCTAssertEqual(Leiste.verschieben(.dienstanweisung, um: -1, in: unten), unten)  // schon ganz links
        XCTAssertEqual(Leiste.entfernen(.meldungen, aus: unten), [.dienstanweisung, .schiffstatus])
    }

    func testSpeichertext() {
        XCTAssertEqual(Leiste.alsText([.schiffstatus, .assetManager]), "schiffstatus,asset_manager")
        // gespeicherte Wahl mit dem Störmeldedienst bzw. Unbekanntem: Unbekanntes fällt weg
        XCTAssertEqual(Leiste.ausText("stoermeldedienst, asset_manager,unbekannt"), [.stoermeldedienst, .assetManager])
        XCTAssertEqual(Leiste.ausText(""), [])
    }
}

final class ScanAuswertungTests: XCTestCase {
    func testEtikettAusKai() {
        XCTAssertEqual(ScanAuswertung.erkennen("https://kai-bsb.de/test/#am_assets?asset=2760"), .kaiGeraet(id: 2760, umgebung: .test))
        XCTAssertEqual(ScanAuswertung.erkennen("https://kai-bsb.de/#am_assets?asset=2760"), .kaiGeraet(id: 2760, umgebung: .produktion))
        XCTAssertEqual(ScanAuswertung.erkennen("https://kai-bsb.de/test/#am_assets_neu?asset=12"), .kaiGeraet(id: 12, umgebung: .test))
        XCTAssertEqual(ScanAuswertung.erkennen(" https://peter.kechel.de/#am_assets?asset=5\n"), .kaiGeraet(id: 5, umgebung: .entwicklung))
    }

    /// Jedes Etikett, das die App selbst druckt, erkennt sie beim Scannen wieder.
    func testEigeneEtikettenWerdenErkannt() {
        for u in Umgebung.allCases {
            XCTAssertEqual(ScanAuswertung.erkennen(u.geraeteLink(321)), .kaiGeraet(id: 321, umgebung: u))
        }
    }

    /// Alte Etiketten zeigen auf bsb-betrieb.de/asset-api/app.html?asset=<alte Nr.> — KAI übersetzt die Nummer.
    func testAlteEtiketten() {
        XCTAssertEqual(ScanAuswertung.erkennen("https://bsb-betrieb.de/asset-api/app.html?asset=10148"), .altesGeraet(altId: 10148))
        XCTAssertEqual(ScanAuswertung.erkennen("https://kai-bsb.de/api/go/asset/10148"), .altesGeraet(altId: 10148))
        XCTAssertEqual(ScanAuswertung.erkennen("https://kai-bsb.de/test/api/go/asset/7646"), .altesGeraet(altId: 7646))
    }

    /// Gerätenamen aus dem Asset Manager (z. B. BSBPC000199, NB0353, SVR-DS01) werden gesucht.
    func testGeraetenamen() {
        for name in ["BSBPC000199", "NB0353", "SVR-DS01", "ESX-PC000036", "BSBMT000229"] {
            XCTAssertEqual(ScanAuswertung.erkennen(name), .suchbegriff(name), name)
        }
        XCTAssertEqual(ScanAuswertung.erkennen("  BSBPC000199 \n"), .suchbegriff("BSBPC000199"))
        XCTAssertEqual(ScanAuswertung.erkennen("DSFC004356"), .suchbegriff("DSFC004356"))   // Seriennummer
    }

    func testAnderesIstText() {
        XCTAssertEqual(ScanAuswertung.erkennen("Hallo Welt"), .text("Hallo Welt"))
        XCTAssertEqual(ScanAuswertung.erkennen("ohneziffer"), .text("ohneziffer"))
        XCTAssertEqual(ScanAuswertung.erkennen("ab"), .text("ab"))
        XCTAssertEqual(ScanAuswertung.erkennen("BSB PC 199"), .text("BSB PC 199"))
        XCTAssertEqual(ScanAuswertung.erkennen("Büro12"), .text("Büro12"))
        guard case .link = ScanAuswertung.erkennen("https://www.bsb.de/fahrplan") else { return XCTFail("fremde Adresse") }
        guard case .link = ScanAuswertung.erkennen("https://kai-bsb.de/#am_assets") else { return XCTFail("ohne Nummer") }
    }

    func testBesterTreffer() {
        func g(_ id: Int, _ name: String, inv: String? = nil, sn: String? = nil) -> GeraetKurz {
            GeraetKurz(id: id, name: name, inventoryNumber: inv, serialNumber: sn, location: nil, deviceType: nil, status: nil)
        }
        let liste = [g(1, "BSBPC000199"), g(2, "BSBPC0001990"), g(3, "NB0353", sn: "DSFC004356")]
        XCTAssertEqual(ScanAuswertung.bester(liste, fuer: "bsbpc000199")?.id, 1)      // genau gleich, ohne Groß/klein
        XCTAssertEqual(ScanAuswertung.bester(liste, fuer: "DSFC004356")?.id, 3)       // über die Seriennummer
        XCTAssertNil(ScanAuswertung.bester(liste, fuer: "BSBPC"))                     // mehrere ungefähr → Auswahl
        XCTAssertEqual(ScanAuswertung.bester([g(9, "PC000344")], fuer: "PC0003")?.id, 9) // einziger Treffer
        XCTAssertNil(ScanAuswertung.bester([], fuer: "X1"))
    }

    /// So antwortet KAI auf /api/go/asset/10148 (Test, 21.11.2026): „location: /#am_assets?asset=2760“.
    func testNummerAusDerUmleitung() {
        XCTAssertEqual(KaiApi.idAusUmleitung("/#am_assets?asset=2760"), 2760)
        XCTAssertEqual(KaiApi.idAusUmleitung("https://kai-bsb.de/test/#am_assets?asset=2760"), 2760)
        XCTAssertNil(KaiApi.idAusUmleitung("/#am_assets"))
        XCTAssertNil(KaiApi.idAusUmleitung("/#home"))
        XCTAssertNil(KaiApi.idAusUmleitung(""))
    }

    func testGeraetAusKaiLesen() throws {
        // Felder wie im Asset Manager (Gerät 2760 = altes Etikett 10148, Datenstand Entwicklung 21.11.2026)
        let json = #"{"id":2760,"name":"BSBIPAD000026","asset_type":"computer","inventory_number":null,"serial_number":"M542NHD750","device_type":"iPad","status":"in_use","macs":[]}"#
        let g = try JSONDecoder().decode(GeraetKurz.self, from: Data(json.utf8))
        XCTAssertEqual(g.id, 2760)
        XCTAssertEqual(g.anzeigename, "BSBIPAD000026")
        XCTAssertEqual(g.serialNumber, "M542NHD750")
        XCTAssertNil(g.inventoryNumber)
        XCTAssertEqual(g.zusatz, "iPad · SN M542NHD750")
    }
}

final class EtikettTests: XCTestCase {
    func testMasse24mm() {
        let m = EtikettMasse.berechnen(band: 24, laenge: 40)
        XCTAssertEqual(m.bandMm, 24)
        XCTAssertEqual(m.laengeMm, 40)
        XCTAssertEqual(m.qrMm, 22)
        XCTAssertEqual(m.pixelBreite, 240)
        XCTAssertEqual(m.pixelHoehe, 400)
    }

    /// Bei 36 mm Band und 40 mm Länge bliebe unter dem QR-Code zu wenig Platz für den Namen → 41 mm.
    func testMasse36mm() {
        let m = EtikettMasse.berechnen(band: 36, laenge: 40)
        XCTAssertEqual(m.qrMm, 34)
        XCTAssertEqual(m.laengeMm, 41)
        XCTAssertEqual(m.pixelBreite, 360)
        XCTAssertEqual(m.pixelHoehe, 410)
    }

    /// Wie in KAI: Etikettenlänge 20–120 mm.
    func testLaengeBegrenzt() {
        XCTAssertEqual(EtikettMasse.berechnen(band: 24, laenge: 500).laengeMm, 120)
        XCTAssertEqual(EtikettMasse.berechnen(band: 24, laenge: 5).laengeMm, 29)   // 20 mm reichen nicht: QR 22 + Rand + Name
        XCTAssertEqual(EtikettMasse.berechnen(band: 24, laenge: 60).laengeMm, 60)
    }

    func testBildGroesseJeBandbreite() {
        for band in EtikettMasse.bandbreiten {
            let m = EtikettMasse.berechnen(band: band, laenge: 50)
            let bild = Etikett.bild(name: "BSBPC000199", qrInhalt: Umgebung.test.geraeteLink(2760), masse: m)
            XCTAssertEqual(bild.cgImage?.width, m.pixelBreite, "\(band) mm")
            XCTAssertEqual(bild.cgImage?.height, m.pixelHoehe, "\(band) mm")
            XCTAssertEqual(bild.size.width, CGFloat(band * 10))
        }
    }

    func testQrCodeEnthaeltDenLink() throws {
        let qr = try XCTUnwrap(Etikett.qrBild(Umgebung.test.geraeteLink(2760), seite: 220))
        XCTAssertEqual(qr.size.width, 220, accuracy: 1)
    }

    func testDruckerNehmenHoechstens24mm() {
        XCTAssertTrue(DruckerModell.ptP710BT.passt(band: 24))
        XCTAssertFalse(DruckerModell.ptP710BT.passt(band: 36))
        XCTAssertFalse(DruckerModell.ptP750W.passt(band: 36))
        XCTAssertTrue(DruckerModell.ptP910BT.passt(band: 36))
        XCTAssertTrue(DruckerModell.ptP910BT.istBluetooth)
        XCTAssertEqual(DruckerModell.ptP910BT.kurz, "P910BT")
    }
}
