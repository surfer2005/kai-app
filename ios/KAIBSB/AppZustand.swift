import SwiftUI

/// Die Reiter der unteren Leiste: links fest „Start“ (KAI-Start in App-Darstellung, ohne Anmeldung die Anmeldeseite), dann die
/// Bereiche, die unten stehen (je Person, s. `Leiste`), rechts fest „Mehr“.
enum Reiter: Hashable {
    case start
    case bereich(Bereich)
    case mehr
}

/// Seiten unter „Mehr“: Bereiche, die nicht unten stehen, dazu Benachrichtigungen, Konto, Drucken, Einstellungen, Leiste anpassen.
enum MehrZiel: Hashable {
    case bereich(Bereich)
    case benachrichtigungen, konto, drucken, einstellungen, leiste
}

/// Startargument `-reiter …` (Bildschirmfotos, Vorführung) → Bereich oder Seite unter „Mehr“.
enum StartZiel: Equatable {
    case bereich(Bereich)
    case mehr([MehrZiel])

    static func aus(_ text: String) -> StartZiel? {
        switch text {
        case "dienstanweisung", "da": .bereich(.dienstanweisung)
        case "meldungen": .bereich(.meldungen)
        case "stoermelde", "stoermeldedienst": .bereich(.stoermeldedienst)
        case "asset": .bereich(.assetManager)
        case "scan": .bereich(.scannen)
        case "info": .bereich(.informationen)
        case "schiffstatus": .bereich(.schiffstatus)
        case "ki": .bereich(.kiChat)
        case "start": nil
        case "mehr": .mehr([])
        case "benachrichtigungen": .mehr([.benachrichtigungen])
        case "konto": .mehr([.konto])
        case "druck": .mehr([.drucken])
        case "einstellungen": .mehr([.einstellungen])
        case "leiste": .mehr([.leiste])
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

/// Zustand der ganzen App: gewählte Umgebung, Rechte aus KAI, Leiste, offener Reiter, die KAI-Seiten.
@MainActor
final class AppZustand: ObservableObject {
    @Published private(set) var umgebung: Umgebung?
    @Published var reiter: Reiter = .start
    @Published var mehrPfad: [MehrZiel] = []
    @Published var offenesGeraet: OffenesGeraet?
    /// Rechte der angemeldeten Person aus KAI (`/api/auth/me` → `permissions`), nil = nicht angemeldet bzw. unbekannt.
    /// Der letzte Stand wird je Umgebung gemerkt (ohne Netz bleiben die Reiter), entscheidet aber nur über die Reiter —
    /// was jemand sehen darf, prüft KAI in jeder Seite selbst.
    @Published private(set) var rechte: [String: String]?
    /// Eigene Wahl der Leiste (Mehr → Leiste anpassen), nil = Vorgabe. Auf dem Gerät gemerkt.
    @Published private(set) var leistenWahl: [Bereich]?
    /// Je Bereich mit KAI-Ansicht eine eigene Seite (Dienstanweisung, Meldungen, Störmeldedienst, Asset Manager, Schiffstatus, KI-Chat).
    @Published private(set) var seiten: [Bereich: WebSteuerung] = [:]
    /// Reiter „Start“: die KAI-Startseite (#home, in der App der Start der App, AppStart.vue) bzw. ohne Anmeldung die Anmeldeseite.
    /// Wird gleich geladen: über sie liest die App die Anmeldung, auch für Scannen und Drucken.
    @Published private(set) var anmeldung: WebSteuerung?
    /// Infocenter-Punkte (Reiter bzw. Punkt „Informationen“), eine Seite für alle Punkte.
    @Published private(set) var informationen: WebSteuerung?
    /// KAI-Seiten unter „Mehr“ (Benachrichtigungen, Mein Konto): KAI blendet in der App seine Kopfleiste mit Glocke und Konto aus
    /// (Peter 2026-11-23), deshalb stehen beide hier. Eine Seite, je nach Punkt auf die passende KAI-Ansicht gestellt.
    @Published private(set) var mehrSeite: WebSteuerung?

    private let speicher = UserDefaults.standard
    private static let schluessel = "kaiUmgebung"
    private static let leistenSchluessel = "kaiLeiste"
    private var rechteAufgabe: Task<Void, Never>?

    init() {
        if Start.zuruecksetzen {
            speicher.removeObject(forKey: Self.schluessel)
            speicher.removeObject(forKey: Self.leistenSchluessel)
        }
        if let text = speicher.string(forKey: Self.leistenSchluessel) { leistenWahl = Leiste.ausText(text) }
        let gespeichert = speicher.string(forKey: Self.schluessel).flatMap(Umgebung.init(rawValue:))
        if let u = Start.umgebung ?? gespeichert { verbinden(u, speichern: Start.umgebung == nil) }
        if let ziel = Start.reiter.flatMap(StartZiel.aus) {
            switch ziel {
            case .bereich(let b): oeffne(b)
            case .mehr(let pfad): reiter = .mehr; mehrPfad = pfad
            }
        }
        if Start.vorfuehrung { offenesGeraet = OffenesGeraet(id: 0, name: "MUSTER", vorfuehrung: true) }
    }

    // MARK: - Leiste

    /// Was unten steht und was unter „Mehr“ — aus den Rechten und der eigenen Wahl.
    var leiste: Leiste {
        guard let rechte else { return Leiste(unten: [], mehr: []) }
        return Leiste.berechnen(rechte: rechte, wahl: leistenWahl)
    }

    /// Die Reiter, die gerade unten stehen: „Start“, die gewählten Bereiche (ohne Anmeldung keine), „Mehr“.
    var reiterUnten: [Reiter] {
        var liste: [Reiter] = [.start]
        if rechte != nil { liste += leiste.unten.map { Reiter.bereich($0) } }
        liste.append(.mehr)
        return liste
    }

    /// Darf die Person den Bereich sehen (nach den zuletzt bekannten Rechten)?
    func darf(_ b: Bereich) -> Bool { rechte.map { b.erlaubt($0) } ?? false }

    /// Eigene Wahl speichern (nil = zurück zur Vorgabe).
    func leisteSetzen(_ wahl: [Bereich]?) {
        leistenWahl = wahl
        if let wahl { speicher.set(Leiste.alsText(wahl), forKey: Self.leistenSchluessel) } else { speicher.removeObject(forKey: Self.leistenSchluessel) }
        reiterPruefen()
    }

    // MARK: - Navigation

    func seite(_ b: Bereich) -> WebSteuerung? { seiten[b] }
    var assetManager: WebSteuerung? { seiten[.assetManager] }

    /// Bereich zeigen: steht er unten, den Reiter wählen — sonst unter „Mehr“ öffnen.
    func oeffne(_ b: Bereich) {
        if rechte != nil, leiste.unten.contains(b) {
            reiter = .bereich(b)
        } else {
            reiter = .mehr
            mehrPfad = [.bereich(b)]
        }
    }

    /// Ist der Bereich gerade auf dem Bildschirm (unten gewählt oder unter „Mehr“ geöffnet)?
    func zeigt(_ b: Bereich) -> Bool {
        reiter == .bereich(b) || (reiter == .mehr && mehrPfad.last == .bereich(b))
    }

    /// Zur KAI-Anmeldung (Einstellungen → „In KAI anmelden“): der Reiter „Start“ zeigt ohne Anmeldung die Anmeldeseite.
    func zumAnmelden() {
        reiter = .start
        mehrPfad = []
    }

    /// Eine Seite unter „Mehr“ öffnen (Drucken, Einstellungen).
    func zeige(_ ziel: MehrZiel) {
        reiter = .mehr
        mehrPfad = [ziel]
    }

    /// Steht der gewählte Reiter nicht mehr unten (Rechte geändert, Leiste angepasst, abgemeldet), den ersten nehmen;
    /// Bereiche ohne Recht verschwinden auch aus dem Weg unter „Mehr“.
    private func reiterPruefen() {
        if !reiterUnten.contains(reiter) { reiter = .start }
        if mehrPfad.contains(where: { if case .bereich(let b) = $0 { return !darf(b) } else { return false } }) { mehrPfad = [] }
    }

    // MARK: - Umgebung und KAI-Seiten

    /// Umgebung wählen (erster Start) bzw. wechseln (Einstellungen). Die KAI-Seiten werden neu aufgebaut.
    func verbinden(_ neu: Umgebung, speichern: Bool = true) {
        if speichern { speicher.set(neu.rawValue, forKey: Self.schluessel) }
        guard neu != umgebung || anmeldung == nil else { return }
        umgebung = neu
        if offenesGeraet?.vorfuehrung != true { offenesGeraet = nil }
        var neueSeiten: [Bereich: WebSteuerung] = [:]
        for b in Bereich.allCases {
            if let ansicht = b.kaiAnsicht { neueSeiten[b] = WebSteuerung(umgebung: neu, startAnsicht: ansicht) }
        }
        let start = WebSteuerung(umgebung: neu, startAnsicht: "home")
        let info = WebSteuerung(umgebung: neu, startAnsicht: "infocenter")
        let mehr = WebSteuerung(umgebung: neu, startAnsicht: "profil")
        for seite in Array(neueSeiten.values) + [start, info, mehr] {
            seite.geraetGeoeffnet = { [weak self] id, name in self?.offenesGeraet = OffenesGeraet(id: id, name: name) }
            seite.anmeldungGeaendert = { [weak self] in self?.rechtePruefen() }
        }
        // Start der App (AppStart.vue): Tipp auf einen Bereich → dorthin; Glocke → Mehr → Benachrichtigungen; Kürzel → Mehr
        start.bereichGewaehlt = { [weak self] b in self?.oeffne(b) }
        start.mehrGewaehlt = { [weak self] ziel in
            guard let self else { return }
            switch ziel {
            case "benachrichtigungen": self.zeige(.benachrichtigungen)
            case "konto": self.zeige(.konto)
            default: self.reiter = .mehr; self.mehrPfad = []
            }
        }
        seiten = neueSeiten
        anmeldung = start
        informationen = info
        mehrSeite = mehr
        rechte = Start.rechte ?? gemerkteRechte(neu)
        reiterPruefen()
        start.erstmalsLaden()   // gleich laden: die Anmeldung brauchen alle Reiter, Scannen und Drucken
    }

    // MARK: - Anmeldung und Rechte

    /// Token der KAI-Anmeldung (aus einer der KAI-Seiten — alle teilen sich den Speicher).
    func token() async -> String? {
        for seite in alleSeiten {
            if let t = await seite.token() { return t }
        }
        return nil
    }

    func api() async -> KaiApi? {
        guard let umgebung else { return nil }
        return KaiApi(umgebung: umgebung, token: await token())
    }

    /// Rechte neu lesen — kurz verzögert, weil KAI beim Anmelden das Token mehrmals schreibt.
    func rechtePruefen() {
        rechteAufgabe?.cancel()
        rechteAufgabe = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.rechteLaden()
        }
    }

    /// Rechte aus KAI lesen (`GET /api/auth/me`). Ohne Anmeldung → nil (nur „Anmelden“ und „Mehr“). Ohne Netz bleibt der letzte Stand.
    func rechteLaden() async {
        guard Start.rechte == nil, let umgebung else { return }
        var geladen = false
        var gefunden: String?
        for seite in alleSeiten {
            switch await seite.anmeldeStand() {
            case .nichtGeladen: continue
            case .ohneNetz: return                 // Offline-Anmeldung am Schiffsterminal: letzter Stand bleibt
            case .abgemeldet: geladen = true
            case .angemeldet(let t): gefunden = t
            }
            if gefunden != nil { break }
        }
        guard let token = gefunden else {
            if geladen { rechteSetzen(nil) }
            return
        }
        do {
            let neu = try await KaiApi(umgebung: umgebung, token: token).rechte()
            rechteSetzen(neu)
        } catch let f as KaiFehler where f.abgemeldet {
            rechteSetzen(nil)
        } catch {
            // ohne Netz bzw. Fehler: die zuletzt bekannten Rechte bleiben
        }
    }

    private func rechteSetzen(_ neu: [String: String]?) {
        guard let umgebung else { return }
        if rechte != neu { rechte = neu }
        let k = "kaiRechte." + umgebung.rawValue
        if let neu, let daten = try? JSONEncoder().encode(neu) { speicher.set(daten, forKey: k) } else { speicher.removeObject(forKey: k) }
        reiterPruefen()
    }

    private func gemerkteRechte(_ u: Umgebung) -> [String: String]? {
        guard let daten = speicher.data(forKey: "kaiRechte." + u.rawValue) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: daten)
    }

    private var alleSeiten: [WebSteuerung] {
        var liste: [WebSteuerung] = []
        if let anmeldung { liste.append(anmeldung) }
        for b in Bereich.allCases { if let s = seiten[b] { liste.append(s) } }
        if let informationen { liste.append(informationen) }
        if let mehrSeite { liste.append(mehrSeite) }
        return liste
    }

    func abmelden() async {
        await anmeldung?.abmelden()
        // nur Seiten, die schon geladen waren (sonst lüden nach dem Abmelden alle KAI-Seiten auf einmal)
        for seite in alleSeiten where seite !== anmeldung && seite.webView.url != nil { seite.zurStartansicht() }
        if Start.rechte == nil { rechteSetzen(nil) }
        mehrPfad = []
        if offenesGeraet?.vorfuehrung != true { offenesGeraet = nil }
    }

    /// Gerät im Asset Manager öffnen und dorthin wechseln.
    func geraetOeffnen(_ id: Int, name: String? = nil) {
        offenesGeraet = OffenesGeraet(id: id, name: name)
        oeffne(.assetManager)
        assetManager?.geraetOeffnen(id)
    }
}
