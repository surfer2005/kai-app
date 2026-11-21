import SwiftUI

/// Die Reiter der unteren Leiste. „Drucken“ und „Einstellungen“ liegen unter „Mehr“ (iOS zeigt höchstens fünf).
enum Reiter: Hashable {
    case assetManager, informationen, ki, scannen, mehr
}

enum MehrZiel: Hashable {
    case drucken, einstellungen
}

extension Reiter {
    /// Startargument `-reiter asset|info|ki|scan|druck|einstellungen|mehr` → Reiter und ggf. Seite unter „Mehr“.
    static func ausStart(_ text: String) -> (Reiter, [MehrZiel])? {
        switch text {
        case "asset": (.assetManager, [])
        case "info": (.informationen, [])
        case "ki": (.ki, [])
        case "scan": (.scannen, [])
        case "mehr": (.mehr, [])
        case "druck": (.mehr, [.drucken])
        case "einstellungen": (.mehr, [.einstellungen])
        default: nil
        }
    }
}

/// Das zuletzt in der App geöffnete Gerät — Grundlage für „Etikett drucken“.
struct OffenesGeraet: Equatable {
    let id: Int
    let name: String?
    /// Nur für die Vorführung (Bildschirmfotos ohne Anmeldung): kein Gerät aus KAI.
    var vorfuehrung = false
}

/// Zustand der ganzen App: gewählte Umgebung, offener Reiter, die KAI-Seiten.
@MainActor
final class AppZustand: ObservableObject {
    @Published private(set) var umgebung: Umgebung?
    @Published var reiter: Reiter = .assetManager
    @Published var mehrPfad: [MehrZiel] = []
    @Published var offenesGeraet: OffenesGeraet?
    @Published private(set) var assetManager: WebSteuerung?
    @Published private(set) var informationen: WebSteuerung?
    @Published private(set) var ki: WebSteuerung?

    private let speicher = UserDefaults.standard
    private static let schluessel = "kaiUmgebung"

    init() {
        if Start.zuruecksetzen { speicher.removeObject(forKey: Self.schluessel) }
        let gespeichert = speicher.string(forKey: Self.schluessel).flatMap(Umgebung.init(rawValue:))
        if let u = Start.umgebung ?? gespeichert { verbinden(u, speichern: Start.umgebung == nil) }
        if let wahl = Start.reiter.flatMap(Reiter.ausStart) { reiter = wahl.0; mehrPfad = wahl.1 }
        if Start.vorfuehrung { offenesGeraet = OffenesGeraet(id: 0, name: "MUSTER", vorfuehrung: true) }
    }

    /// Umgebung wählen (erster Start) bzw. wechseln (Einstellungen). Die KAI-Seiten werden neu aufgebaut.
    func verbinden(_ neu: Umgebung, speichern: Bool = true) {
        if speichern { speicher.set(neu.rawValue, forKey: Self.schluessel) }
        guard neu != umgebung || assetManager == nil else { return }
        umgebung = neu
        if offenesGeraet?.vorfuehrung != true { offenesGeraet = nil }
        let am = WebSteuerung(umgebung: neu, startAnsicht: "am_assets_neu")
        let info = WebSteuerung(umgebung: neu, startAnsicht: "infocenter")
        let kiChat = WebSteuerung(umgebung: neu, startAnsicht: "ki_chat")
        for seite in [am, info, kiChat] {
            seite.geraetGeoeffnet = { [weak self] id, name in self?.offenesGeraet = OffenesGeraet(id: id, name: name) }
        }
        assetManager = am
        informationen = info
        ki = kiChat
        am.erstmalsLaden()   // gleich laden: die Anmeldung braucht auch „Scannen“ und „Drucken“
    }

    /// Gerät im Asset Manager öffnen und dorthin wechseln.
    func geraetOeffnen(_ id: Int, name: String? = nil) {
        offenesGeraet = OffenesGeraet(id: id, name: name)
        reiter = .assetManager
        assetManager?.geraetOeffnen(id)
    }

    /// Eine Seite unter „Mehr“ öffnen (Drucken, Einstellungen).
    func zeige(_ ziel: MehrZiel) {
        reiter = .mehr
        mehrPfad = [ziel]
    }

    /// Token der KAI-Anmeldung (aus einer der KAI-Seiten — alle teilen sich den Speicher).
    func token() async -> String? {
        for seite in [assetManager, informationen, ki] {
            if let t = await seite?.token() { return t }
        }
        return nil
    }

    func api() async -> KaiApi? {
        guard let umgebung else { return nil }
        return KaiApi(umgebung: umgebung, token: await token())
    }

    func abmelden() async {
        await assetManager?.abmelden()
        informationen?.zurStartansicht()
        ki?.zurStartansicht()
        if offenesGeraet?.vorfuehrung != true { offenesGeraet = nil }
    }
}
