import SwiftUI

enum Reiter: String, Hashable {
    case assetManager = "asset"
    case informationen = "info"
    case scannen = "scan"
    case drucken = "druck"
    case einstellungen
}

/// Das zuletzt in der App geöffnete Gerät — Grundlage für das Etikett im Reiter „Drucken“.
struct OffenesGeraet: Equatable {
    let id: Int
    let name: String?
    /// Nur für die Vorführung (Bildschirmfotos ohne Anmeldung): kein Gerät aus KAI.
    var vorfuehrung = false
}

/// Zustand der ganzen App: gewählte Umgebung, offener Reiter, die beiden KAI-Seiten.
@MainActor
final class AppZustand: ObservableObject {
    @Published private(set) var umgebung: Umgebung?
    @Published var reiter: Reiter = .assetManager
    @Published var offenesGeraet: OffenesGeraet?
    @Published private(set) var assetManager: WebSteuerung?
    @Published private(set) var informationen: WebSteuerung?

    private let speicher = UserDefaults.standard
    private static let schluessel = "kaiUmgebung"

    init() {
        if Start.zuruecksetzen { speicher.removeObject(forKey: Self.schluessel) }
        let gespeichert = speicher.string(forKey: Self.schluessel).flatMap(Umgebung.init(rawValue:))
        if let u = Start.umgebung ?? gespeichert { verbinden(u, speichern: Start.umgebung == nil) }
        if let r = Start.reiter.flatMap(Reiter.init(rawValue:)) { reiter = r }
        if Start.vorfuehrung { offenesGeraet = OffenesGeraet(id: 0, name: "MUSTER", vorfuehrung: true) }
    }

    /// Umgebung wählen (erster Start) bzw. wechseln (Einstellungen). Beide KAI-Seiten werden neu aufgebaut.
    func verbinden(_ neu: Umgebung, speichern: Bool = true) {
        if speichern { speicher.set(neu.rawValue, forKey: Self.schluessel) }
        guard neu != umgebung || assetManager == nil else { return }
        umgebung = neu
        if offenesGeraet?.vorfuehrung != true { offenesGeraet = nil }
        let am = WebSteuerung(umgebung: neu, startAnsicht: "am_assets_neu")
        let info = WebSteuerung(umgebung: neu, startAnsicht: "infocenter")
        for seite in [am, info] {
            seite.geraetGeoeffnet = { [weak self] id, name in self?.offenesGeraet = OffenesGeraet(id: id, name: name) }
        }
        assetManager = am
        informationen = info
        am.erstmalsLaden()   // gleich laden: die Anmeldung braucht auch „Scannen“ und „Drucken“
    }

    /// Gerät im Asset Manager öffnen und dorthin wechseln.
    func geraetOeffnen(_ id: Int, name: String? = nil) {
        offenesGeraet = OffenesGeraet(id: id, name: name)
        reiter = .assetManager
        assetManager?.geraetOeffnen(id)
    }

    /// Token der KAI-Anmeldung (aus einer der beiden Seiten).
    func token() async -> String? {
        if let t = await assetManager?.token() { return t }
        return await informationen?.token()
    }

    func api() async -> KaiApi? {
        guard let umgebung else { return nil }
        return KaiApi(umgebung: umgebung, token: await token())
    }

    func abmelden() async {
        await assetManager?.abmelden()
        informationen?.zurStartansicht()
        if offenesGeraet?.vorfuehrung != true { offenesGeraet = nil }
    }
}
