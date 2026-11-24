import Foundation

/// Die drei KAI-Umgebungen. Gewählt beim ersten Start, änderbar in den Einstellungen.
/// Die Adressen sind dieselben wie im Browser — die App zeigt die KAI-Seiten selbst an.
enum Umgebung: String, CaseIterable, Identifiable, Codable {
    case test, produktion, entwicklung

    var id: String { rawValue }

    /// Basisadresse ohne Schrägstrich am Ende.
    var adresse: String {
        switch self {
        case .test: "https://kai-bsb.de/test"
        case .produktion: "https://kai-bsb.de"
        case .entwicklung: "https://peter.kechel.de"
        }
    }

    var name: String {
        switch self {
        case .test: "Test"
        case .produktion: "Produktion"
        case .entwicklung: "Entwicklung"
        }
    }

    /// Kennzeichen im Kopf. In der Produktion keins — wie in KAI selbst (Setting `environment_label`).
    var kennzeichen: String? {
        switch self {
        case .test: "TEST"
        case .produktion: nil
        case .entwicklung: "ENTWICKLUNG"
        }
    }

    var beschreibung: String {
        switch self {
        case .test: "Zum Ausprobieren an einer Kopie der echten Daten."
        case .produktion: "Das echte KAI — Änderungen gelten sofort für alle."
        case .entwicklung: "Gemeinsamer Entwicklungsserver."
        }
    }

    /// Die Startseite (mit Schrägstrich am Ende — die Testumgebung leitet `/test` sonst erst um).
    var startseite: URL { URL(string: adresse + "/")! }

    var host: String { URL(string: adresse)?.host ?? "" }

    /// Adresse einer KAI-Ansicht über ihre Hash-Route, z. B. `am_assets_neu` oder `zielanzeiger`.
    func ansicht(_ hash: String) -> URL {
        URL(string: adresse + "/#" + hash)!
    }

    /// Adresse eines KAI-API-Wegs, z. B. `asset-manager/assets/12`.
    func api(_ pfad: String) -> URL {
        URL(string: adresse + "/api/" + pfad)!
    }

    /// Inhalt des QR-Codes auf dem Geräte-Etikett — genau wie KAI ihn druckt
    /// (`assetDeepLink()` in AssetManagerView: `origin + BASE_URL + #am_assets?asset=<id>`).
    func geraeteLink(_ id: Int) -> String {
        adresse + "/#am_assets?asset=\(id)"
    }

    /// Gehört eine Adresse zu dieser Umgebung? Test und Produktion teilen sich den Rechner kai-bsb.de,
    /// sie unterscheiden sich nur am Pfad `/test`.
    func enthaelt(_ url: URL?) -> Bool {
        guard let url else { return false }
        return Umgebung.zu(url: url) == self
    }

    /// Zu welcher Umgebung gehört eine Adresse (z. B. ein gescanntes Etikett)? Unbekannte Rechner → nil.
    static func zu(url: URL) -> Umgebung? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "peter.kechel.de" { return .entwicklung }
        if host == "kai-bsb.de" || host == "www.kai-bsb.de" {
            let pfad = url.path
            return (pfad == "/test" || pfad.hasPrefix("/test/")) ? .test : .produktion
        }
        return nil
    }

    /// Vorgabe beim ersten Start (aus `KAI_UMGEBUNG_VORGABE` in project.yml), sonst Test.
    static var vorgabe: Umgebung {
        let text = Bundle.main.object(forInfoDictionaryKey: "KAIUmgebungVorgabe") as? String ?? ""
        return Umgebung(rawValue: text) ?? .test
    }
}

/// Startargumente für Bildschirmfotos und Vorführung, z. B. `-umgebung test -reiter einstellungen`.
enum Start {
    static func wert(_ name: String) -> String? {
        let argumente = ProcessInfo.processInfo.arguments
        guard let i = argumente.firstIndex(of: "-" + name), i + 1 < argumente.count else { return nil }
        return argumente[i + 1]
    }

    static func schalter(_ name: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains("-" + name)
    }

    /// Umgebung für diesen Start festlegen (überspringt die Einrichtung).
    static var umgebung: Umgebung? { wert("umgebung").flatMap(Umgebung.init(rawValue:)) }
    /// Gespeicherte Wahl vergessen → Einrichtung wie beim ersten Start.
    static var zuruecksetzen: Bool { schalter("zuruecksetzen") }
    /// Welcher Reiter beim Start offen ist: dienstanweisung, meldungen, asset, scan, info, schiffstatus, ki, bordbuch
    /// (steht der Bereich nicht unten, öffnet er sich unter „Mehr“), mehr, benachrichtigungen, konto, druck, einstellungen, leiste;
    /// `start-<Bereich>` (z. B. start-info) öffnet den Bereich im Reiter „Start“ wie ein Tipp auf seine Kachel.
    static var reiter: String? { wert("reiter") }
    /// Vorführung/Bildschirmfotos ohne Anmeldung: Rechte für die Reiter vorgeben, statt sie aus KAI zu lesen —
    /// `alle` oder eine Liste der KAI-Rechte, z. B. `dienstanweisung,meldungen,schiffstatus` (jeweils Leserecht).
    static var rechte: [String: String]? {
        guard let w = wert("rechte") else { return nil }
        let schluessel = w == "alle"
            ? Bereich.allCases.compactMap(\.recht)
            : w.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Dictionary(schluessel.map { ($0, "read") }, uniquingKeysWith: { a, _ in a })
    }
    /// Vorführung ohne Anmeldung: „Etikett drucken“ zeigt ein deutlich gekennzeichnetes Muster-Etikett.
    static var vorfuehrung: Bool { schalter("vorfuehrung") }
}

enum AppInfo {
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }
}
