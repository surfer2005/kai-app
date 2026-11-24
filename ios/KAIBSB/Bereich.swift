import Foundation

/// Die Bereiche der App — jeder steht als Reiter unten in der Leiste oder unter „Mehr“.
/// Reihenfolge wie im Klick-Dummy „KAI-App“ (BEREICHE: Dienstanweisung, Meldungen, Störmeldedienst, Asset Manager, Scannen,
/// Informationen, Schiffstatus, KI-Chat), ganz hinten das Bordbuch zum Lesen (Peter 2026-11-23).
/// Der Störmeldedienst zeigt in KAI den Ablauf „Störmeldung auslösen“ (Handy-Ansicht des Klick-Dummys „Anzeiger“, Peter 2026-11-24);
/// er steht unter „Mehr“ bzw. als Kachel auf Start — die Vorgabe der Leiste bleibt Dienstanweisung · Meldungen · Bordbuch.
enum Bereich: String, CaseIterable, Identifiable, Codable {
    case dienstanweisung
    case meldungen
    case stoermeldedienst
    case assetManager = "asset_manager"
    case scannen
    case informationen
    case schiffstatus
    case kiChat = "ki_chat"
    case bordbuch

    var id: String { rawValue }

    /// Name wie in KAI.
    var name: String {
        switch self {
        case .dienstanweisung: "Dienstanweisung"
        case .meldungen: "Meldungen"
        case .stoermeldedienst: "Störmeldedienst"
        case .assetManager: "Asset Manager"
        case .scannen: "Scannen"
        case .informationen: "Informationen"
        case .schiffstatus: "Schiffstatus"
        case .kiChat: "KI-Chat"
        case .bordbuch: "Bordbuch"
        }
    }

    /// Name in der Leiste unten (im Dummy heißt der Asset Manager dort „Assets“).
    var leistenName: String {
        switch self {
        case .assetManager: "Assets"
        default: name
        }
    }

    /// SF Symbol — entspricht dem Material-Symbol im Dummy (campaign, report, warning, devices, qr_code_scanner, info, directions_boat,
    /// forum, menu_book).
    var symbol: String {
        switch self {
        case .dienstanweisung: "megaphone"
        case .meldungen: "exclamationmark.octagon"
        case .stoermeldedienst: "exclamationmark.triangle"
        case .assetManager: "laptopcomputer.and.iphone"
        case .scannen: "qrcode.viewfinder"
        case .informationen: "info.circle"
        case .schiffstatus: "ferry"
        case .kiChat: "bubble.left.and.bubble.right"
        case .bordbuch: "book.closed"
        }
    }

    /// Das Recht in KAI, das zum Lesen nötig ist (Schlüssel aus `/api/auth/me` → `permissions`).
    /// Informationen stehen allen offen — jeder Punkt des Infocenters prüft in KAI selbst.
    var recht: String? {
        switch self {
        case .dienstanweisung: "dienstanweisung"
        case .meldungen: "meldungen"
        case .stoermeldedienst: "stoermeldedienst"
        case .assetManager, .scannen: "asset_manager"
        case .informationen: nil
        case .schiffstatus: "schiffstatus"
        case .kiChat: "ki_chat"
        case .bordbuch: "bordbuch"
        }
    }

    /// Die KAI-Ansicht (Hash-Route) — nil bei den Bereichen, die die App selbst zeigt (Scannen, Liste der Informationen).
    var kaiAnsicht: String? {
        switch self {
        case .dienstanweisung: "dienstanweisung"
        case .meldungen: "meldungen"
        case .stoermeldedienst: "stoermeldedienst"   // in der App nur der Ablauf „Störmeldung auslösen“, ohne Reiter
        case .assetManager: "am_assets_neu"
        case .schiffstatus: "schiffstatus"
        case .kiChat: "ki_chat"
        case .bordbuch: "bordbuch"   // KAI zeigt es in der App nur zum Lesen (BordbuchLesen.vue)
        case .scannen, .informationen: nil
        }
    }

    /// Darf die Person den Bereich sehen? Leserecht genügt (`read` oder `write`).
    func erlaubt(_ rechte: [String: String]) -> Bool {
        guard let recht else { return true }
        let stufe = rechte[recht] ?? "none"
        return stufe == "read" || stufe == "write"
    }
}

/// Welche Bereiche unten in der Leiste stehen und welche unter „Mehr“.
/// Die Leiste: ganz links fest „Start“, ganz rechts fest „Mehr“, dazwischen höchstens DREI Bereiche (iOS: fünf Plätze; Klick-Dummy
/// „KAI-App“, LEISTE_MAX = 3). KAI bestimmt über die Rechte, WAS jemand sieht; die Person wählt unter „Mehr → Leiste anpassen“, welche
/// drei unten stehen und in welcher Reihenfolge (Peter 2026-11-23). Ohne eigene Wahl gilt die Vorgabe.
struct Leiste: Equatable {
    let unten: [Bereich]
    let mehr: [Bereich]

    static let hoechstens = 3

    /// Alle Bereiche, die die Person nach ihren Rechten sehen darf — in der festen Reihenfolge.
    static func sichtbar(_ rechte: [String: String]) -> [Bereich] {
        Bereich.allCases.filter { $0.erlaubt(rechte) }
    }

    /// Vorgabe der Leiste (Peter 2026-11-24): Dienstanweisung · Meldungen · Bordbuch in dieser Reihenfolge.
    static let vorgabeReihenfolge: [Bereich] = [.dienstanweisung, .meldungen, .bordbuch]

    /// Vorgabe: die Bereiche aus `vorgabeReihenfolge`, die die Person sehen darf; fehlt ihr ein Recht, rücken die nächsten sichtbaren
    /// Bereiche in der festen Reihenfolge nach — höchstens drei.
    static func vorgabe(_ rechte: [String: String]) -> [Bereich] {
        let alle = sichtbar(rechte)
        let zuerst = vorgabeReihenfolge.filter { alle.contains($0) }
        return Array((zuerst + alle.filter { !zuerst.contains($0) }).prefix(hoechstens))
    }

    /// Leiste aus Rechten und gespeicherter Wahl (nil = keine eigene Wahl → Vorgabe). Ein Bereich, für den das Recht weggefallen
    /// ist, fällt auch aus der gespeicherten Wahl. Bleibt von einer (nicht leeren) Wahl nichts übrig, gilt die Vorgabe.
    static func berechnen(rechte: [String: String], wahl: [Bereich]?) -> Leiste {
        let alle = sichtbar(rechte)
        var unten: [Bereich]
        if let wahl {
            var gesehen = Set<Bereich>()
            unten = Array(wahl.filter { alle.contains($0) && gesehen.insert($0).inserted }.prefix(hoechstens))
            if unten.isEmpty && !wahl.isEmpty { unten = vorgabe(rechte) }
        } else {
            unten = vorgabe(rechte)
        }
        return Leiste(unten: unten, mehr: alle.filter { !unten.contains($0) })
    }

    // MARK: - Ändern (für „Leiste anpassen“) — liefern die neue Wahl

    /// Bereich nach unten in die Leiste holen (hinten anhängen), solange Platz ist.
    static func hinzufuegen(_ b: Bereich, zu unten: [Bereich]) -> [Bereich] {
        guard !unten.contains(b), unten.count < hoechstens else { return unten }
        return unten + [b]
    }

    /// Bereich aus der Leiste nehmen (steht dann unter „Mehr“).
    static func entfernen(_ b: Bereich, aus unten: [Bereich]) -> [Bereich] {
        unten.filter { $0 != b }
    }

    /// Bereich in der Leiste um eine Stelle verschieben (nach links: -1, nach rechts: +1).
    static func verschieben(_ b: Bereich, um schritt: Int, in unten: [Bereich]) -> [Bereich] {
        guard let i = unten.firstIndex(of: b) else { return unten }
        let ziel = i + schritt
        guard unten.indices.contains(ziel) else { return unten }
        var neu = unten
        neu.swapAt(i, ziel)
        return neu
    }

    /// Wahl als Text für den Speicher („dienstanweisung,meldungen“) und zurück; unbekannte Namen fallen weg.
    static func alsText(_ wahl: [Bereich]) -> String { wahl.map(\.rawValue).joined(separator: ",") }
    static func ausText(_ text: String) -> [Bereich] {
        text.split(separator: ",").compactMap { Bereich(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
    }
}
