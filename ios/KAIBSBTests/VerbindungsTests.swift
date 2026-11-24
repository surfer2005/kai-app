import XCTest
import Network
import SwiftUI
import WebKit
@testable import KAIBSB

// Peter 2026-11-24 am iPhone (Test, Stand 4e5df3a7): „Störmeldedienst wird nur Lädt angezeigt“, „KI-Chat zeigt nichts an“.
// Im Protokoll von Test kam von diesen Seiten keine Anfrage an — bis 10:59:01, da kamen sie alle auf einmal, zusammen mit den
// liegengebliebenen Anfragen anderer Seiten. Ursache: jede angemeldete KAI-Seite hält einen Ereignisstrom des Mitarbeiter-Chats
// offen (`/api/chat/stream`), KAI spricht nur HTTP/1.1, und alle Seiten der App teilen sich die Verbindungen zum Server.
// Die Prüfungen hier führen das mit einem kleinen HTTP/1.1-Server im Simulator vor (Gegenprobe ohne das Skript der App) und
// halten fest, dass mit dem Skript (`WebSteuerung.ereignisstromSkript`) jede Seite durchkommt.

/// Kleiner HTTP/1.1-Server nur für die Prüfungen — wie KAI hinter nginx: HTTP/1.1, Verbindungen bleiben offen (keep-alive),
/// Ereignisströme enden nie. Wege: `/seite?n=…` (Prüfseite, öffnet einen Ereignisstrom wie `ChatWidget.vue`),
/// `/strom?n=…` (der Ereignisstrom), `/abruf?tag=…` (ein gewöhnlicher Abruf wie `api.stoermeldungStand()`).
final class PruefServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "de.kaibsb.pruefserver")
    private var seiten: Set<String> = []
    private var abrufe: Set<String> = []
    private var stroeme: [ObjectIdentifier: (verbindung: NWConnection, n: String)] = [:]
    private var stromAnfragen: [String] = []
    private var ticker: DispatchSourceTimer?
    private(set) var port: UInt16 = 0

    static let seite = """
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Prüfseite</title></head>
    <body><p>Prüfseite</p><script>
    var q = new URLSearchParams(location.search);
    if (!q.get('ohne')) { window.strom = new EventSource('/strom?n=' + q.get('n')); window.strom.onmessage = function () {}; }
    window.abruf = function (tag) { fetch('/abruf?tag=' + encodeURIComponent(tag), { cache: 'no-store' }); return 1; };
    </script></body></html>
    """

    init() throws {
        let parameter = NWParameters.tcp
        parameter.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameter, on: .any)
    }

    func starten() throws {
        let bereit = DispatchSemaphore(value: 0)
        let fehlerKasten = FehlerKasten()
        listener.stateUpdateHandler = { zustand in
            switch zustand {
            case .ready: bereit.signal()
            case .failed(let f): fehlerKasten.fehler = f; bereit.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] verbindung in self?.annehmen(verbindung) }
        listener.start(queue: queue)
        guard bereit.wait(timeout: .now() + 5) == .success else { throw NSError(domain: "PruefServer", code: 1) }
        if let f = fehlerKasten.fehler { throw f }
        port = listener.port?.rawValue ?? 0
        // Lebenszeichen auf allen offenen Strömen (KAI: alle 25 s) — zeigt zugleich, wenn die App eine Verbindung geschlossen hat
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.lebenszeichen() }
        t.resume()
        ticker = t
    }

    func stoppen() {
        queue.sync {
            ticker?.cancel()
            for s in stroeme.values { s.verbindung.cancel() }
            stroeme = [:]
        }
        listener.cancel()
    }

    var offeneStroeme: Int { queue.sync { stroeme.count } }
    func stromOffen(_ n: String) -> Bool { queue.sync { stroeme.values.contains { $0.n == n } } }
    func stromAnfragen(_ n: String) -> Int { queue.sync { stromAnfragen.filter { $0 == n }.count } }
    func seiteDa(_ n: String) -> Bool { queue.sync { seiten.contains(n) } }
    func abrufDa(_ tag: String) -> Bool { queue.sync { abrufe.contains(tag) } }

    private func annehmen(_ verbindung: NWConnection) {
        verbindung.start(queue: queue)
        lesen(verbindung, Data())
    }

    private func lesen(_ verbindung: NWConnection, _ puffer: Data) {
        verbindung.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] daten, _, fertig, fehler in
            guard let self else { return }
            var p = puffer
            if let daten { p.append(daten) }
            if let ende = p.range(of: Data("\r\n\r\n".utf8)) {
                let kopf = String(decoding: p[p.startIndex..<ende.lowerBound], as: UTF8.self)
                let rest = Data(p[ende.upperBound...])
                if self.anfrage(kopf, verbindung) { self.lesen(verbindung, rest) }
                return
            }
            if fertig || fehler != nil { self.schliessen(verbindung); return }
            self.lesen(verbindung, p)
        }
    }

    /// Bearbeitet eine Anfrage. true = die Verbindung nimmt weitere Anfragen an (keep-alive), false = Ereignisstrom.
    private func anfrage(_ kopf: String, _ verbindung: NWConnection) -> Bool {
        let zeile = kopf.components(separatedBy: "\r\n").first ?? ""
        let teile = zeile.split(separator: " ")
        guard teile.count >= 2, let komponenten = URLComponents(string: "http://pruef" + String(teile[1])) else {
            schliessen(verbindung)
            return false
        }
        let wert = { (name: String) in komponenten.queryItems?.first { $0.name == name }?.value ?? "" }
        switch komponenten.path {
        case "/seite":
            seiten.insert(wert("n"))
            antworten(verbindung, "text/html; charset=utf-8", Self.seite)
            return true
        case "/abruf":
            abrufe.insert(wert("tag"))
            antworten(verbindung, "text/plain", "ok")
            return true
        case "/strom":
            stromAnfragen.append(wert("n"))
            stroeme[ObjectIdentifier(verbindung)] = (verbindung, wert("n"))
            let antwort = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\nretry: 3000\n\n"
            verbindung.send(content: Data(antwort.utf8), completion: .contentProcessed { _ in })
            stromBeobachten(verbindung)
            return false
        default:
            antworten(verbindung, "text/plain", "", status: "404 Not Found")
            return true
        }
    }

    private func antworten(_ verbindung: NWConnection, _ art: String, _ text: String, status: String = "200 OK") {
        let koerper = Data(text.utf8)
        let kopf = "HTTP/1.1 \(status)\r\nContent-Type: \(art)\r\nContent-Length: \(koerper.count)\r\nCache-Control: no-store\r\nConnection: keep-alive\r\n\r\n"
        verbindung.send(content: Data(kopf.utf8) + koerper, completion: .contentProcessed { _ in })
    }

    /// Ein Ereignisstrom bleibt offen, bis die App die Verbindung schließt.
    private func stromBeobachten(_ verbindung: NWConnection) {
        verbindung.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, fertig, fehler in
            guard let self else { return }
            if fertig || fehler != nil { self.schliessen(verbindung) } else { self.stromBeobachten(verbindung) }
        }
    }

    private func lebenszeichen() {
        for s in Array(stroeme.values) {
            s.verbindung.send(content: Data(": ping\n\n".utf8), completion: .contentProcessed { [weak self] fehler in
                if fehler != nil { self?.schliessen(s.verbindung) }
            })
        }
    }

    private func schliessen(_ verbindung: NWConnection) {
        stroeme[ObjectIdentifier(verbindung)] = nil
        verbindung.cancel()
    }
}

private final class FehlerKasten: @unchecked Sendable { var fehler: Error? }

/// Wartet (höchstens `frist` Sekunden), bis die Bedingung gilt — und lässt dabei die Hauptschleife laufen (WebKit, SwiftUI).
@MainActor
func warten(_ frist: TimeInterval, _ bedingung: () -> Bool) -> Bool {
    let ende = Date().addingTimeInterval(frist)
    while !bedingung() {
        if Date() > ende { return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return true
}

/// Ein eigenes, sichtbares Fenster in der Szene der App (über der App), für Ansichten in den Prüfungen.
@MainActor
func pruefFenster() throws -> UIWindow {
    let szene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first, "keine Fensterszene")
    let fenster = UIWindow(windowScene: szene)
    fenster.frame = szene.coordinateSpace.bounds
    fenster.windowLevel = .alert + 1
    fenster.rootViewController = UIViewController()
    fenster.isHidden = false
    return fenster
}

/// Merkt sich, ob eine Seite fertig geladen hat oder woran sie gescheitert ist (z. B. App Transport Security).
@MainActor
final class LadeBeobachter: NSObject, WKNavigationDelegate {
    var fertig = false
    var fehler: String?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { fertig = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fehler = Self.text(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fehler = Self.text(error) }
    nonisolated static func text(_ e: Error) -> String { let n = e as NSError; return "\(n.domain) \(n.code): \(n.localizedDescription)" }
}

/// Eine Seite, wie die App sie nutzt: sichtbar laden, abrufen, wieder ausblenden (anderer Reiter, Bereich darüber geöffnet).
struct SeitenMessung: CustomStringConvertible {
    let n: Int
    var seiteGeladen = false
    var stromOffen = false
    var abrufAngekommen = false
    var offeneStroeme = 0
    var fehler: String?
    var description: String {
        "Seite \(n): geladen \(seiteGeladen ? "ja" : "NEIN"), Ereignisstrom \(stromOffen ? "offen" : "nicht offen"), "
            + "Abruf \(abrufAngekommen ? "angekommen" : "NICHT angekommen"), offene Ströme am Server \(offeneStroeme)"
            + (fehler.map { " — Ladefehler: \($0)" } ?? "")
    }
}

@MainActor
final class VerbindungsTests: XCTestCase {
    /// So viele Seiten öffnet man in der App schnell: Start, drei Reiter unten, Informationen, Asset Manager, Schiffstatus,
    /// Störmeldedienst, Liegeplatz … (Peter am 24.11. zwischen 10:48 und 10:56: acht).
    let anzahl = 9
    /// Fristen großzügig: im Simulator der CI braucht der erste Web-/Netzwerkprozess bis zu 15 s zum Starten (Lauf 45373228670).
    let fristSeite: TimeInterval = 20

    /// Basisadresse des Prüfservers, die WebKit lädt: zuerst `localhost`, sonst `127.0.0.1`. Prüft vorher, ob der Server selbst
    /// antwortet (URLSession), damit ein Fehlschlag sagt, woran es liegt.
    private func basisAdresse(_ server: PruefServer, _ fenster: UIWindow) throws -> String {
        final class Kasten: @unchecked Sendable { var text: String? }
        let direkt = Kasten()
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:\(server.port)/abruf?tag=urlsession")!) { _, antwort, fehler in
            let t = fehler.map { LadeBeobachter.text($0) } ?? "Status \((antwort as? HTTPURLResponse)?.statusCode ?? 0)"
            DispatchQueue.main.async { direkt.text = t }
        }.resume()
        _ = warten(15) { direkt.text != nil }
        print("Verbindungsprobe: Prüfserver auf Port \(server.port), direkt (URLSession): \(direkt.text ?? "keine Antwort")")
        var gruende: [String] = []
        for host in ["localhost", "127.0.0.1"] {
            let probe = WKWebView(frame: fenster.bounds, configuration: WebSteuerung.konfiguration())
            let beobachter = LadeBeobachter()
            probe.navigationDelegate = beobachter
            fenster.addSubview(probe)
            let n = "probe-\(host)"
            probe.load(URLRequest(url: URL(string: "http://\(host):\(server.port)/seite?ohne=1&n=\(n)")!))
            _ = warten(45) { server.seiteDa(n) || beobachter.fehler != nil }
            probe.removeFromSuperview()
            let ok = server.seiteDa(n)
            print("Verbindungsprobe: WebKit über \(host): \(ok ? "erreichbar" : "nicht erreichbar — \(beobachter.fehler ?? "Zeitüberschreitung")")")
            if ok { return "http://\(host):\(server.port)" }
            gruende.append("\(host): \(beobachter.fehler ?? "Zeitüberschreitung")")
        }
        throw NSError(domain: "Verbindungsprobe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Prüfserver im Simulator nicht erreichbar (\(gruende.joined(separator: "; ")))"])
    }

    /// Lädt `anzahl` Seiten nacheinander sichtbar, ruft in jeder ab und blendet sie wieder aus; danach eine weitere, die sichtbar bleibt.
    /// `abbrechenNach`: nach so vielen Seiten in Folge ohne Abruf aufhören (Gegenprobe — der Engpass ist dann gezeigt).
    private func messen(ereignisstroeme: Bool, server: PruefServer, fenster: UIWindow, basis: String, seiten: inout [WKWebView],
                        beobachter: inout [LadeBeobachter], abbrechenNach: Int = .max) -> [SeitenMessung] {
        var zeilen: [SeitenMessung] = []
        var ohneAbruf = 0
        let art = ereignisstroeme ? "mit" : "OHNE"
        for k in 1...(anzahl + 1) {
            let w = WKWebView(frame: fenster.bounds, configuration: WebSteuerung.konfiguration(ereignisstroeme: ereignisstroeme))
            let b = LadeBeobachter()
            w.navigationDelegate = b
            seiten.append(w)
            beobachter.append(b)
            fenster.addSubview(w)
            var m = SeitenMessung(n: k)
            w.load(URLRequest(url: URL(string: "\(basis)/seite?n=\(k)")!))
            _ = warten(fristSeite) { server.seiteDa("\(k)") || b.fehler != nil }
            m.seiteGeladen = server.seiteDa("\(k)")
            if m.seiteGeladen { m.stromOffen = warten(10) { server.stromOffen("\(k)") } }
            _ = warten(5) { b.fertig || b.fehler != nil }
            m.fehler = b.fehler
            let tag = "\(ereignisstroeme ? "mit" : "ohne")-\(k)"
            w.evaluateJavaScript("window.abruf && window.abruf('\(tag)')", completionHandler: nil)
            m.abrufAngekommen = warten(6) { server.abrufDa(tag) }
            if k <= anzahl {
                w.removeFromSuperview()   // anderer Reiter / Bereich darüber: die Seite ist nicht mehr zu sehen
                if ereignisstroeme { _ = warten(8) { !server.stromOffen("\(k)") } } else { _ = warten(1) { false } }
            }
            m.offeneStroeme = server.offeneStroeme
            zeilen.append(m)
            print("Verbindungsprobe (\(art) Skript der App): \(m)")
            ohneAbruf = m.abrufAngekommen ? 0 : ohneAbruf + 1
            if ohneAbruf >= abbrechenNach {
                print("Verbindungsprobe (\(art) Skript der App): \(ohneAbruf) Seiten in Folge ohne Abruf — Messung beendet.")
                break
            }
        }
        return zeilen
    }

    /// Mit dem Skript der App: jede Seite kommt durch, egal wie viele schon offen sind; offen bleibt nur der Strom der sichtbaren
    /// Seite, und eine Seite, die wieder zu sehen ist, verbindet ihren Strom neu.
    func testEreignisstroemeNurInDerSichtbarenSeite() throws {
        let server = try PruefServer()
        try server.starten()
        let fenster = try pruefFenster()
        var seiten: [WKWebView] = []
        var beobachter: [LadeBeobachter] = []
        defer {
            for w in seiten { w.stopLoading(); w.removeFromSuperview() }
            server.stoppen()
            fenster.isHidden = true
        }
        let basis = try basisAdresse(server, fenster)
        let zeilen = messen(ereignisstroeme: true, server: server, fenster: fenster, basis: basis, seiten: &seiten, beobachter: &beobachter)
        for m in zeilen {
            XCTAssertTrue(m.seiteGeladen, "\(m)")
            XCTAssertTrue(m.abrufAngekommen, "\(m)")
            XCTAssertTrue(m.stromOffen, "solange die Seite zu sehen ist, ist ihr Strom offen — \(m)")
        }
        // nur die sichtbare Seite hält einen Strom
        XCTAssertTrue(warten(10) { server.offeneStroeme == 1 }, "offene Ströme: \(server.offeneStroeme)")
        // Seite 1 wieder zeigen (zurück in den Reiter): ihr Strom kommt wieder, Abrufe gehen durch
        let vorher = server.stromAnfragen("1")
        fenster.addSubview(seiten[0])
        XCTAssertTrue(warten(15) { server.stromAnfragen("1") > vorher && server.stromOffen("1") }, "Strom von Seite 1 nicht neu verbunden")
        seiten[0].evaluateJavaScript("window.abruf('mit-wieder-1')", completionHandler: nil)
        XCTAssertTrue(warten(6) { server.abrufDa("mit-wieder-1") })
        print("Verbindungsprobe (mit Skript der App): Seite 1 wieder sichtbar → Strom neu verbunden, Abruf angekommen; offene Ströme \(server.offeneStroeme)")
    }

    /// Gegenprobe: dieselben Seiten OHNE das Skript der App — so verhielt sich die App bis Lauf 45341663507.
    /// Hält nur fest, was passiert (WebKit kann seine Grenzen ändern), und schreibt es ins Protokoll des Laufs.
    func testGegenprobeOhneSkriptDerApp() throws {
        let server = try PruefServer()
        try server.starten()
        let fenster = try pruefFenster()
        var seiten: [WKWebView] = []
        var beobachter: [LadeBeobachter] = []
        defer {
            for w in seiten { w.stopLoading(); w.removeFromSuperview() }
            server.stoppen()
            fenster.isHidden = true
        }
        let basis = try basisAdresse(server, fenster)
        let zeilen = messen(ereignisstroeme: false, server: server, fenster: fenster, basis: basis, seiten: &seiten,
                            beobachter: &beobachter, abbrechenNach: 2)
        if let erste = zeilen.first(where: { !$0.abrufAngekommen }) {
            print("Verbindungsprobe (OHNE Skript der App): ab Seite \(erste.n) kam der Abruf nicht mehr an — \(erste.offeneStroeme) Ereignisströme hielten die Verbindungen.")
        } else {
            print("Verbindungsprobe (OHNE Skript der App): alle Abrufe kamen an — der Engpass trat hier nicht auf.")
        }
    }
}

/// Eine KAI-Seite hängt immer nur in EINER Ansicht — der, die gerade auf dem Bildschirm ist (Kachel auf Start und derselbe
/// Bereich über „Mehr“, Peter 2026-11-24).
@MainActor
final class SeitenOrtTests: XCTestCase {
    func testRahmenNimmtDieSeiteNurImFenster() throws {
        let fenster = try pruefFenster()
        defer { fenster.isHidden = true }
        let seite = WebSteuerung(umgebung: .test, startAnsicht: "ki_chat")
        let start = WebRahmen(), mehr = WebRahmen(), draussen = WebRahmen()
        for r in [start, mehr, draussen] { r.steuerung = seite }

        draussen.einhaengen()
        XCTAssertNil(seite.webView.superview, "ein Rahmen außerhalb des Fensters nimmt die Seite nicht")

        fenster.addSubview(start)           // Kachel auf Start
        XCTAssertTrue(seite.webView.superview === start)

        start.removeFromSuperview()         // Reiter „Mehr“ gewählt, dort derselbe Bereich
        fenster.addSubview(mehr)
        XCTAssertTrue(seite.webView.superview === mehr)
        XCTAssertFalse(start.subviews.contains(seite.webView))

        draussen.einhaengen()
        XCTAssertTrue(seite.webView.superview === mehr, "ein unsichtbarer Rahmen stiehlt die Seite nicht")

        mehr.removeFromSuperview()          // zurück zu „Start“
        fenster.addSubview(start)
        XCTAssertTrue(seite.webView.superview === start)

        WebAnsicht.dismantleUIView(mehr, coordinator: ())      // der Ort unter „Mehr“ wird abgebaut
        XCTAssertTrue(seite.webView.superview === start, "Abbau eines anderen Rahmens lässt die Seite, wo sie ist")
        XCTAssertTrue(seite.webView.window === fenster)

        WebAnsicht.dismantleUIView(start, coordinator: ())
        XCTAssertNil(seite.webView.superview)
    }

    /// Wie in der App (TabView + Navigation): Kachel „KI-Chat“ auf Start, derselbe Bereich über „Mehr“, zurück zu Start.
    func testKachelAufStartUndUeberMehrNieDoppelt() throws {
        let app = AppZustand()
        app.verbinden(.test, speichern: false)
        // ohne Anmeldung würden die Seiten nach dem Laden die (fehlenden) Rechte melden und den Weg leeren — hier nicht
        let alle = Bereich.allCases.compactMap { app.seite($0) } + [app.anmeldung, app.informationen, app.mehrSeite].compactMap { $0 }
        for s in alle { s.anmeldungGeaendert = nil }
        let fenster = try pruefFenster()
        defer { fenster.isHidden = true }
        fenster.rootViewController = UIHostingController(rootView: HauptAnsicht().environmentObject(app))
        let start = try XCTUnwrap(app.anmeldung)
        let ki = try XCTUnwrap(app.seite(.kiChat))
        XCTAssertTrue(warten(5) { start.webView.window === fenster }, "Start zeigt die KAI-Startseite")

        app.kachelGewaehlt(.kiChat)        // Kachel auf Start
        XCTAssertEqual(app.reiter, .start)
        XCTAssertEqual(app.startPfad, [.kiChat])
        XCTAssertTrue(warten(5) { ki.webView.window === fenster }, "KI-Chat im Reiter Start zu sehen")
        let rahmenStart = try XCTUnwrap(ki.webView.superview as? WebRahmen)

        app.mehrPfad = [.bereich(.kiChat)]  // derselbe Bereich über „Mehr“
        app.reiter = .mehr
        XCTAssertTrue(warten(5) { ki.webView.window === fenster && ki.webView.superview !== rahmenStart }, "KI-Chat unter Mehr zu sehen")
        let rahmenMehr = try XCTUnwrap(ki.webView.superview as? WebRahmen)
        XCTAssertFalse(rahmenStart.subviews.contains(ki.webView), "nicht doppelt eingehängt")

        app.reiter = .start                 // zurück in den Reiter Start: die Seite kommt mit
        XCTAssertTrue(warten(5) { ki.webView.window === fenster && ki.webView.superview !== rahmenMehr }, "KI-Chat wieder im Reiter Start")

        app.startPfad = []                  // Zurück → Start
        XCTAssertTrue(warten(5) { ki.webView.window == nil && start.webView.window === fenster }, "Zurück führt zu Start")
        XCTAssertEqual(app.reiter, .start)
        XCTAssertEqual(app.mehrPfad, [.bereich(.kiChat)], "„Mehr“ bleibt unberührt")
    }
}
