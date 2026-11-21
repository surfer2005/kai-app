import Foundation

/// Was ein gescannter Code (QR oder Barcode) bedeutet.
enum ScanErgebnis: Equatable {
    /// Geräte-Etikett aus KAI: `…/#am_assets?asset=<id>` (bzw. `#am_assets_neu`). `umgebung` = woher das Etikett stammt.
    case kaiGeraet(id: Int, umgebung: Umgebung?)
    /// Etikett aus dem alten Asset Manager (`bsb-betrieb.de/asset-api/app.html?asset=<alte Nr.>`)
    /// oder der Sprung `/api/go/asset/<alte Nr.>` — KAI übersetzt die alte Nummer.
    case altesGeraet(altId: Int)
    /// Gerätename bzw. Inventarnummer (z. B. „BSBPC000199“) oder Seriennummer — wird im Asset Manager gesucht.
    case suchbegriff(String)
    /// Eine Adresse, die nicht zu KAI gehört.
    case link(URL)
    /// Sonst irgendein Text.
    case text(String)
}

enum ScanAuswertung {
    static func erkennen(_ roh: String) -> ScanErgebnis {
        let text = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), let schema = url.scheme?.lowercased(), schema == "http" || schema == "https",
           let host = url.host, !host.isEmpty {
            // 1. Etikett aus KAI
            if let fragment = url.fragment, fragment.hasPrefix("am_assets"), let id = zahl(nach: "asset=", in: fragment) {
                return .kaiGeraet(id: id, umgebung: Umgebung.zu(url: url))
            }
            // 2. Sprung für alte Nummern (KAI selbst oder das Portal)
            if let bereich = url.path.range(of: "/api/go/asset/") {
                if let id = Int(url.path[bereich.upperBound...].prefix(while: \.isNumber)), id > 0 {
                    return .altesGeraet(altId: id)
                }
            }
            // 3. Altes Etikett: …/asset-api/app.html?asset=<alte Nr.>
            let pfad = url.path.lowercased()
            if pfad.contains("/asset-api") || pfad.hasSuffix("/app.html") {
                let teile = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if let wert = teile?.queryItems?.first(where: { $0.name == "asset" })?.value, let id = Int(wert), id > 0 {
                    return .altesGeraet(altId: id)
                }
                // ganz alte App-Fassung: …#/assets/<alte Nr.>
                if let fragment = url.fragment, let bereich = fragment.range(of: "/assets/"),
                   let id = Int(fragment[bereich.upperBound...].prefix(while: \.isNumber)), id > 0 {
                    return .altesGeraet(altId: id)
                }
            }
            return .link(url)
        }
        if istGeraetename(text) { return .suchbegriff(text) }
        return .text(text)
    }

    /// Gerätenamen und Inventarnummern in KAI bestehen aus Buchstaben, Ziffern und wenigen Zeichen, ohne Leerzeichen,
    /// und tragen eine Ziffer (z. B. „BSBPC000199“, „NB0353“, „SVR-DS01“). Reine Ziffernfolgen sind oft Seriennummern.
    static func istGeraetename(_ text: String) -> Bool {
        guard (3...40).contains(text.count) else { return false }
        let erlaubt = Set("-_./")
        let nurErlaubt = text.allSatisfy { zeichen in
            zeichen.isASCII && (zeichen.isLetter || zeichen.isNumber || erlaubt.contains(zeichen))
        }
        return nurErlaubt && text.contains(where: \.isNumber)
    }

    /// Welcher Suchtreffer ist gemeint? Name, Inventar- oder Seriennummer genau gleich (ohne Groß/klein) gewinnt;
    /// sonst nur, wenn es genau einen Treffer gibt. Mehrere ungefähre Treffer → nil (Auswahl zeigen).
    static func bester(_ treffer: [GeraetKurz], fuer begriff: String) -> GeraetKurz? {
        let gesucht = begriff.lowercased()
        let genau = treffer.filter { g in
            [g.name, g.inventoryNumber, g.serialNumber].contains { $0?.lowercased() == gesucht }
        }
        if genau.count == 1 { return genau[0] }
        if genau.isEmpty, treffer.count == 1 { return treffer[0] }
        return nil
    }

    /// Erste Zahl hinter `schluessel` in `text`, z. B. 12 aus „am_assets?asset=12“.
    static func zahl(nach schluessel: String, in text: String) -> Int? {
        guard let bereich = text.range(of: schluessel) else { return nil }
        let ziffern = text[bereich.upperBound...].prefix(while: \.isNumber)
        guard let id = Int(ziffern), id > 0 else { return nil }
        return id
    }
}
