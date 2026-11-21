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
    /// Drucken und Einstellungen liegen unter „Mehr“ — die Startargumente führen trotzdem direkt hin.
    func testStartargumente() {
        XCTAssertEqual(Reiter.ausStart("ki")?.0, .ki)
        XCTAssertEqual(Reiter.ausStart("druck")?.0, .mehr)
        XCTAssertEqual(Reiter.ausStart("druck")?.1, [.drucken])
        XCTAssertEqual(Reiter.ausStart("einstellungen")?.1, [.einstellungen])
        XCTAssertEqual(Reiter.ausStart("asset")?.1, [])
        XCTAssertNil(Reiter.ausStart("unbekannt"))
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
    }
}
