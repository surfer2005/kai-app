import SwiftUI
import UIKit

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

/// Startargument `-reiter …` (Bildschirmfotos, Vorführung) → Bereich, Seite unter „Mehr“ oder Bereich im Reiter „Start“
/// (`start-info` = wie nach einem Tipp auf die Kachel „Informationen“).
enum StartZiel: Equatable {
    case bereich(Bereich)
    case mehr([MehrZiel])
    case start([Bereich])

    static func aus(_ text: String) -> StartZiel? {
        if text.hasPrefix("start-") {
            guard case .some(.bereich(let b)) = aus(String(text.dropFirst("start-".count))) else { return nil }
            return .start([b])
        }
        return switch text {
        case "dienstanweisung", "da": .bereich(.dienstanweisung)
        case "meldungen": .bereich(.meldungen)
        case "stoermeldedienst", "stoer": .bereich(.stoermeldedienst)
        case "asset": .bereich(.assetManager)
        case "scan": .bereich(.scannen)
        case "info": .bereich(.informationen)
        case "schiffstatus": .bereich(.schiffstatus)
        case "ki": .bereich(.kiChat)
        case "bordbuch": .bereich(.bordbuch)
        case "liegeplatz": .bereich(.liegeplatz)
        case "dienste": .bereich(.meineDienste)   // sinnvoll als start-dienste (nur auf Start)
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

/// Wo man gerade steht: gewählter Reiter und der Weg in den Reitern „Start“ und „Mehr“ — rein, damit die Prüfungen nachrechnen
/// können, wohin ein Tipp führt.
struct Weg: Equatable {
    var reiter: Reiter = .start
    var startPfad: [Bereich] = []
    var mehrPfad: [MehrZiel] = []

    /// Kachel auf Start (Peter 2026-11-28, vorher 2026-11-24): JEDE Kachel öffnet ihren Bereich in der Navigation des Reiters
    /// „Start“ — oben links „‹ Start“, Wischen vom linken Rand führt zu Start zurück. Das gilt auch für Bereiche, die zusätzlich
    /// unten in der Leiste stehen (vorher wechselte die Kachel dort auf den Reiter, und es gab kein Zurück zu Start). Ein Tipp unten
    /// auf den Reiter bleibt der Weg ohne Pfeil. „Mehr“ und die übrigen Reiter bleiben unberührt.
    func kachel(_ b: Bereich) -> Weg {
        var neu = self
        neu.reiter = .start
        neu.startPfad = [b]
        return neu
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
    /// Weg im Reiter „Start“: ein Bereich, der über eine Kachel auf Start geöffnet wurde und nicht unten steht.
    @Published var startPfad: [Bereich] = []
    @Published var mehrPfad: [MehrZiel] = []
    @Published var offenesGeraet: OffenesGeraet?

    /// Erneutes Tippen auf den aktiven Reiter: zum Anfang. Start → Kachel-Weg schließen, KAI-Start zeigen; ein KAI-Bereich →
    /// seine Startansicht neu laden (schließt auch einen geöffneten Datensatz — der ändert die Adresse in KAI nicht); Mehr → zur Liste.
    /// Ist in der Seite etwas ungespeichert, fragt sie vorher (WebSteuerung.nachRueckfrage).
    func reiterNochmalGetippt(_ r: Reiter) {
        switch r {
        case .start:
            if let start = anmeldung {
                start.nachRueckfrage { [weak self] in self?.startPfad = []; start.startansichtZeigen() }
            } else { startPfad = [] }
        case .bereich(let b):
            if let s = seite(b) { s.nachRueckfrage { s.zurStartansicht() } }
        case .mehr:
            mehrPfad = []
        }
    }

    // MARK: - Zahlen an den Reitern (Peter 2026-11-27)

    /// Ungelesene Dienstanweisungen (wie „n neu“ auf Start, `GET /api/directives/ungelesen`).
    @Published private(set) var zahlDienstanweisung = 0
    /// Ungelesene Benachrichtigungen (Glocke, `GET /api/notifications?nurAnzahl=1`).
    @Published private(set) var zahlBenachrichtigungen = 0
    private var zaehlerAufgabe: Task<Void, Never>?

    /// Zahl am Reiter „Mehr“: Benachrichtigungen, dazu die Dienstanweisungen, wenn die unter „Mehr“ stehen.
    var zahlMehr: Int {
        zahlBenachrichtigungen + (rechte != nil && leiste.mehr.contains(.dienstanweisung) ? zahlDienstanweisung : 0)
    }

    /// Kurz verzögert neu lesen (mehrere Anstöße hintereinander zählen einmal).
    func zaehlerPruefen() {
        zaehlerAufgabe?.cancel()
        zaehlerAufgabe = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.zaehlerLaden()
        }
    }

    func zaehlerLaden() async {
        guard rechte != nil, let api = await api(), api.token != nil else { zahlDienstanweisung = 0; zahlBenachrichtigungen = 0; return }
        if darf(.dienstanweisung), let n = try? await api.zahl("directives/ungelesen", feld: "anzahl") { zahlDienstanweisung = n }
        if let n = try? await api.zahl("notifications?nurAnzahl=1", feld: "unread") { zahlBenachrichtigungen = n }
    }

    // MARK: - Kurzbefehle am App-Symbol (lange drücken, Peter 2026-11-27)

    /// Nur, was die Person darf: Neue Meldung (Schreibrecht), Dienstanweisung, Bordbuch, Informationen.
    func kurzbefehleSetzen() {
        var liste: [UIApplicationShortcutItem] = []
        func eintrag(_ typ: String, _ titel: String, _ symbol: String) {
            liste.append(UIApplicationShortcutItem(type: typ, localizedTitle: titel, localizedSubtitle: nil,
                                                   icon: UIApplicationShortcutIcon(systemImageName: symbol)))
        }
        if let rechte {
            if rechte["meldungen"] == "write" { eintrag(Kurzbefehl.neueMeldung, "Neue Meldung", "square.and.pencil") }
            for b in [Bereich.dienstanweisung, .bordbuch, .informationen] where darf(b) { eintrag(Kurzbefehl.bereich + b.rawValue, b.name, b.symbol) }
        }
        UIApplication.shared.shortcutItems = Array(liste.prefix(4))
    }

    /// Ein Kurzbefehl wurde gewählt (KurzbefehlPost): Bereich öffnen, bei „Neue Meldung“ gleich das Formular (KAI: #meldungen?neu=1).
    func kurzbefehl(_ typ: String) {
        guard rechte != nil else { return }
        if typ == Kurzbefehl.neueMeldung, darf(.meldungen) {
            oeffne(.meldungen)
            seite(.meldungen)?.zeigen("meldungen?neu=1")
        } else if typ.hasPrefix(Kurzbefehl.bereich), let b = Bereich(rawValue: String(typ.dropFirst(Kurzbefehl.bereich.count))), darf(b) {
            oeffne(b)
        }
    }
    /// Rechte der angemeldeten Person aus KAI (`/api/auth/me` → `permissions`), nil = nicht angemeldet bzw. unbekannt.
    /// Der letzte Stand wird je Umgebung gemerkt (ohne Netz bleiben die Reiter), entscheidet aber nur über die Reiter —
    /// was jemand sehen darf, prüft KAI in jeder Seite selbst.
    @Published private(set) var rechte: [String: String]?
    /// Eigene Wahl der Leiste (Mehr → Leiste anpassen), nil = Vorgabe. Auf dem Gerät gemerkt.
    @Published private(set) var leistenWahl: [Bereich]?
    /// Je Bereich mit KAI-Ansicht eine eigene Seite (Dienstanweisung, Meldungen, Asset Manager, Schiffstatus, KI-Chat, Bordbuch).
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
            case .start(let pfad):
                // wie ein Tipp auf die Kachel in AppStart.vue: derselbe Weg wie die Nachricht der Seite (bereichGewaehlt → kachelGewaehlt)
                if pfad.count == 1, let tipp = anmeldung?.bereichGewaehlt { tipp(pfad[0]) } else { reiter = .start; startPfad = pfad }
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

    /// Kachel auf Start: immer im Reiter „Start“ öffnen, mit „‹ Start“ (s. `Weg.kachel`).
    func kachelGewaehlt(_ b: Bereich) {
        let neu = Weg(reiter: reiter, startPfad: startPfad, mehrPfad: mehrPfad).kachel(b)
        if startPfad != neu.startPfad { startPfad = neu.startPfad }
        if reiter != neu.reiter { reiter = neu.reiter }
    }

    /// Ist der Bereich gerade auf dem Bildschirm (unten gewählt, unter „Mehr“ oder im Reiter „Start“ geöffnet)?
    func zeigt(_ b: Bereich) -> Bool {
        reiter == .bereich(b) || (reiter == .mehr && mehrPfad.last == .bereich(b)) || (reiter == .start && startPfad.last == b)
    }

    /// Zur KAI-Anmeldung (Einstellungen → „In KAI anmelden“): der Reiter „Start“ zeigt ohne Anmeldung die Anmeldeseite.
    func zumAnmelden() {
        reiter = .start
        startPfad = []
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
        if startPfad.contains(where: { !darf($0) }) { startPfad = [] }
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
            seite.zaehlerGeaendert = { [weak self] in self?.zaehlerPruefen() }
        }
        // Start der App (AppStart.vue): Kachel → Reiter des Bereichs bzw. im Reiter „Start“ öffnen; Glocke → Mehr → Benachrichtigungen;
        // Kürzel → Mehr
        start.bereichGewaehlt = { [weak self] b in self?.kachelGewaehlt(b) }
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
        kurzbefehleSetzen()
        zaehlerPruefen()
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
        startPfad = []
        mehrPfad = []
        if offenesGeraet?.vorfuehrung != true { offenesGeraet = nil }
    }

    /// Gerät im Asset Manager öffnen und dorthin wechseln — aus Scannen, das über Start geöffnet wurde, im Reiter „Start“.
    func geraetOeffnen(_ id: Int, name: String? = nil) {
        offenesGeraet = OffenesGeraet(id: id, name: name)
        if reiter == .start, !startPfad.isEmpty { kachelGewaehlt(.assetManager) } else { oeffne(.assetManager) }
        assetManager?.geraetOeffnen(id)
    }
}
