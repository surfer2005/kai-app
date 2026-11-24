import SwiftUI
import UIKit
import WebKit

/// Stand der Anmeldung in einer KAI-Seite.
enum AnmeldeStand: Equatable {
    /// Seite noch nicht (fertig) geladen — keine Aussage möglich.
    case nichtGeladen
    /// Offline-Anmeldung am Schiffsterminal (Platzhalter-Token) — keine Aussage über die Rechte.
    case ohneNetz
    case abgemeldet
    case angemeldet(String)
}

/// Eine KAI-Seite in der App (je Bereich eine). Alle teilen sich den Website-Speicher des iPhones:
/// die Anmeldung (Token `lpv_token` im localStorage, wie im Browser) gilt in allen und bleibt nach dem Schließen erhalten.
/// Sie teilen sich damit auch die Verbindungen des iPhones zu KAI (s. `ereignisstromSkript`).
@MainActor
final class WebSteuerung: NSObject, ObservableObject {
    @Published private(set) var kannZurueck = false
    @Published private(set) var laedt = false
    @Published private(set) var fehler: String?

    let webView: WKWebView
    let umgebung: Umgebung
    let startAnsicht: String
    /// Meldet, wenn in der KAI-Seite ein Gerät geöffnet wurde (id, Name) — für „Etikett drucken“.
    var geraetGeoeffnet: ((Int, String?) -> Void)?
    /// Meldet, wenn sich die Anmeldung geändert haben kann (Seite geladen, KAI hat das Token geschrieben oder entfernt) —
    /// die App liest dann die Rechte neu und stellt die Reiter danach.
    var anmeldungGeaendert: (() -> Void)?
    /// Start der App (KAI AppStart.vue, `anAppMelden`): ein Bereich wurde angetippt bzw. Glocke/Kürzel („mehr“, Ziel).
    var bereichGewaehlt: ((Bereich) -> Void)?
    var mehrGewaehlt: ((String) -> Void)?

    private var beobachter: [NSKeyValueObservation] = []
    private var geladen = false
    /// Die Seite war mindestens einmal fertig geladen (didFinish). Vorher darf kein Skript laufen: ein `location.hash` im noch
    /// leeren Dokument bricht das Laden ab (Bildschirmfoto 23.11.: Reiter „Start“ blieb leer).
    private var einmalFertig = false

    init(umgebung: Umgebung, startAnsicht: String) {
        self.umgebung = umgebung
        self.startAnsicht = startAnsicht
        let konfiguration = Self.konfiguration()
        let inhalt = konfiguration.userContentController
        webView = WKWebView(frame: .zero, configuration: konfiguration)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Farbe.hintergrund)
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        super.init()
        inhalt.add(SchwacherBote(self), name: "kaiApp")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        beobachter = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] ansicht, _ in
                Task { @MainActor in self?.kannZurueck = ansicht.canGoBack }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] ansicht, _ in
                Task { @MainActor in self?.laedt = ansicht.isLoading }
            },
        ]
    }

    /// Einstellungen jeder KAI-Seite — eine Stelle, damit die Prüfungen dieselben Skripte laden wie die App.
    /// `ereignisstroeme: false` nur für die Gegenprobe in den Prüfungen (KAI-Seite ohne das Skript der App).
    static func konfiguration(ereignisstroeme: Bool = true) -> WKWebViewConfiguration {
        let konfiguration = WKWebViewConfiguration()
        konfiguration.websiteDataStore = .default()
        konfiguration.applicationNameForUserAgent = "KAI-BSB-App/\(AppInfo.version)"
        konfiguration.allowsInlineMediaPlayback = true
        // KI-Chat „Vorlesen“: KAI spielt die Antwort ab, sobald der Ton fertig ist (nach dem Tippen, aber nicht
        // unmittelbar darin) — deshalb Wiedergabe ohne eigenen Tipp erlauben.
        konfiguration.mediaTypesRequiringUserActionForPlayback = []
        let inhalt = WKUserContentController()
        inhalt.addUserScript(WKUserScript(source: beobachterSkript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if ereignisstroeme {
            inhalt.addUserScript(WKUserScript(source: ereignisstromSkript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        konfiguration.userContentController = inhalt
        return konfiguration
    }

    /// Lädt die Startansicht beim ersten Anzeigen (nicht schon beim Start der App).
    func erstmalsLaden() {
        guard !geladen else { return }
        geladen = true
        webView.load(URLRequest(url: umgebung.ansicht(startAnsicht)))
    }

    func zurStartansicht() {
        geladen = true
        fehler = nil
        webView.load(URLRequest(url: umgebung.ansicht(startAnsicht)))
    }

    /// Steht die Seite (fertig geladen) auf einer anderen KAI-Ansicht, zurück zur Startansicht — für den Reiter „Start“,
    /// der keine eigene Kopfleiste mit Zurück hat.
    func startansichtZeigen() {
        guard einmalFertig, !webView.isLoading, umgebung.enthaelt(webView.url) else { return }
        if (webView.url?.fragment ?? "").split(separator: "?").first.map(String.init) != startAnsicht { zeigen(startAnsicht) }
    }

    func neuLaden() {
        fehler = nil
        if webView.url == nil { zurStartansicht() } else { webView.reload() }
    }

    func zurueck() { if webView.canGoBack { webView.goBack() } }

    /// Eine KAI-Ansicht über ihre Hash-Route zeigen (z. B. `zielanzeiger`).
    func zeigen(_ hash: String) {
        fehler = nil
        guard geladen, !webView.isLoading, umgebung.enthaelt(webView.url) else {
            geladen = true
            webView.load(URLRequest(url: umgebung.ansicht(hash)))
            return
        }
        webView.evaluateJavaScript("location.hash = \(Self.jsText("#" + hash)); null", completionHandler: nil)
    }

    /// Ein Gerät im Asset Manager öffnen. KAI liest `?asset=` nur beim Öffnen der Ansicht — ist der Asset Manager
    /// schon offen, wird die Seite deshalb neu geladen (sonst bliebe das vorige Gerät stehen).
    func geraetOeffnen(_ id: Int) {
        fehler = nil
        let ziel = "am_assets_neu?asset=\(id)"
        guard geladen, umgebung.enthaelt(webView.url) else {
            geladen = true
            webView.load(URLRequest(url: umgebung.ansicht(ziel)))
            return
        }
        let skript = """
        (function () {
          var ziel = \(Self.jsText("#" + ziel));
          var jetzt = location.hash.split('?')[0];
          if (jetzt === '#am_assets_neu' || jetzt === '#am_assets') {
            var u = new URL(location.href); u.searchParams.set('app', String(Date.now())); u.hash = ziel;
            location.replace(u.toString());
          } else { location.hash = ziel; }
        })(); null
        """
        webView.evaluateJavaScript(skript, completionHandler: nil)
    }

    /// Token der Anmeldung aus der KAI-Seite (leer = nicht angemeldet). Wie KAI selbst (error-report.js): zuerst der
    /// sessionStorage (Anmeldung von außerhalb des Firmennetzes, endet mit dem Fenster), sonst der localStorage.
    func token() async -> String? {
        if case .angemeldet(let t) = await anmeldeStand() { return t }
        return nil
    }

    /// Anmeldung in dieser Seite: noch nicht geladen, ohne Netz (Offline-Anmeldung), abgemeldet oder angemeldet (Token).
    func anmeldeStand() async -> AnmeldeStand {
        guard umgebung.enthaelt(webView.url), !webView.isLoading else { return .nichtGeladen }
        let wert: String = await withCheckedContinuation { fertig in
            webView.evaluateJavaScript("(function(){ try { return sessionStorage.getItem('lpv_token') || localStorage.getItem('lpv_token') || '' } catch (e) { return '' } })()") { ergebnis, _ in
                fertig.resume(returning: (ergebnis as? String) ?? "")
            }
        }
        if wert.isEmpty { return .abgemeldet }
        if wert == "offline" { return .ohneNetz }
        return .angemeldet(wert)
    }

    /// Abmelden wie in KAI: Token entfernen und die Seite neu laden (zeigt dann die Anmeldung).
    func abmelden() async {
        guard umgebung.enthaelt(webView.url) else { return }
        _ = await withCheckedContinuation { (fertig: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript("try { localStorage.removeItem('lpv_token'); sessionStorage.removeItem('lpv_token') } catch (e) {}; null") { _, _ in fertig.resume() }
        }
        zurStartansicht()
    }

    fileprivate func nachricht(_ inhalt: Any) {
        guard let d = inhalt as? [String: Any] else { return }
        switch (d["art"] as? String) ?? "" {
        case "anmeldung": anmeldungGeaendert?(); return
        case "bereich":
            if let id = d["id"] as? String, let b = Bereich(rawValue: id) { bereichGewaehlt?(b) }
            return
        case "mehr": mehrGewaehlt?((d["ziel"] as? String) ?? ""); return
        default: break
        }
        guard d["art"] as? String == "geraet" else { return }
        let id = (d["id"] as? Int) ?? (d["id"] as? NSNumber)?.intValue ?? 0
        guard id > 0 else { return }
        let name = (d["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        geraetGeoeffnet?(id, name)
    }

    /// Text sicher in ein Skript einsetzen.
    static func jsText(_ s: String) -> String {
        let daten = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let feld = String(decoding: daten, as: UTF8.self)
        return String(feld.dropFirst().dropLast())
    }

    /// Merkt, welches Gerät die KAI-Seite gerade lädt: KAI holt ein geöffnetes Gerät über
    /// `GET /api/asset-manager/assets/<id>`. Ändert nichts an der Seite, liest nur mit.
    /// Dazu: schreibt oder entfernt KAI das Token (`lpv_token`, Anmelden/Abmelden/Erneuern), meldet die Seite das der App.
    static let beobachterSkript = """
    (function () {
      if (window.__kaiApp) return; window.__kaiApp = true;
      var melden = function (d) { try { window.webkit.messageHandlers.kaiApp.postMessage(d) } catch (e) {} };
      try {
        var sp = Storage.prototype, setzen = sp.setItem, entfernen = sp.removeItem;
        sp.setItem = function (k) { var r = setzen.apply(this, arguments); if (k === 'lpv_token') melden({ art: 'anmeldung' }); return r; };
        sp.removeItem = function (k) { var r = entfernen.apply(this, arguments); if (k === 'lpv_token') melden({ art: 'anmeldung' }); return r; };
      } catch (e) {}
      var muster = /\\/api\\/asset-manager\\/assets\\/(\\d+)(?:\\?|$)/;
      var original = window.fetch;
      if (!original) return;
      window.fetch = function (eingabe, optionen) {
        var url = typeof eingabe === 'string' ? eingabe : (eingabe && eingabe.url) || '';
        var art = ((optionen && optionen.method) || (eingabe && eingabe.method) || 'GET').toUpperCase();
        var antwort = original.apply(this, arguments);
        var m = muster.exec(url);
        if (m && art === 'GET') {
          antwort.then(function (r) {
            if (!r.ok) return;
            r.clone().json().then(function (j) {
              melden({ art: 'geraet', id: Number(m[1]), name: (j && j.name) || '' });
            }).catch(function () {});
          }).catch(function () {});
        }
        return antwort;
      };
    })();
    """

    /// Ereignisströme (`EventSource`) nur in der Seite, die gerade zu sehen ist (Peter 2026-11-24: Störmeldedienst blieb bei
    /// „Lädt …“, KI-Chat leer). Jede angemeldete KAI-Seite öffnet für den Mitarbeiter-Chat einen Ereignisstrom
    /// (`ChatWidget.vue` → `GET /api/chat/stream`), der nie endet. KAI antwortet nur über HTTP/1.1, und alle Seiten der App teilen
    /// sich EINEN Netzwerkspeicher und damit dieselben wenigen Verbindungen zum Server. Mit jeder geöffneten Seite (Start, die
    /// Reiter unten, Bereiche über Start und „Mehr“) war eine Verbindung mehr dauerhaft belegt; danach blieb jede weitere Anfrage
    /// still in der Warteschlange des iPhones — „Lädt …“ ohne Fehler, beim Server kam nichts an (Protokoll Test 24.11.).
    /// Dieses Skript ersetzt `EventSource` durch eine Hülle mit derselben Bedienung: die echte Verbindung besteht nur, solange
    /// die Seite sichtbar ist (`document.visibilityState`); verschwindet sie (anderer Reiter, Bereich darüber geöffnet, App im
    /// Hintergrund), wird sie geschlossen, und kommt die Seite zurück, neu geöffnet. KAI selbst bleibt unverändert — der Chat holt
    /// Ungelesenes ohnehin alle 30 s nach.
    static let ereignisstromSkript = """
    (function () {
      var Echt = window.EventSource;
      if (!Echt || Echt.__kaiApp) return;
      var alle = [];
      var sichtbar = function () { return document.visibilityState !== 'hidden'; };
      var STANDARD = { open: 1, message: 1, error: 1 };
      class KaiEreignisstrom extends EventTarget {
        constructor(url, optionen) {
          super();
          this.url = new URL(url, location.href).href;
          this.withCredentials = !!(optionen && optionen.withCredentials);
          this.onopen = null; this.onmessage = null; this.onerror = null;
          this._optionen = optionen; this._echt = null; this._zu = false;
          this._arten = new Set(['open', 'message', 'error']);
          alle.push(this);
          if (sichtbar()) this._verbinden();
        }
        get readyState() { return this._zu ? 2 : (this._echt ? this._echt.readyState : 0); }
        addEventListener(art, f, o) {
          super.addEventListener(art, f, o);
          if (!this._arten.has(art)) { this._arten.add(art); if (this._echt) this._weiterleiten(this._echt, art); }
        }
        close() {
          this._zu = true; this._trennen();
          var i = alle.indexOf(this); if (i >= 0) alle.splice(i, 1);
        }
        _verbinden() {
          if (this._zu || this._echt) return;
          var e = new Echt(this.url, this._optionen);
          this._echt = e;
          var self = this;
          this._arten.forEach(function (art) { self._weiterleiten(e, art); });
        }
        _trennen() { var e = this._echt; this._echt = null; if (e) e.close(); }
        _weiterleiten(e, art) {
          var self = this;
          e.addEventListener(art, function (ev) {
            if (self._echt !== e) return;
            var kopie = (typeof MessageEvent === 'function' && ev instanceof MessageEvent)
              ? new MessageEvent(art, { data: ev.data, origin: ev.origin, lastEventId: ev.lastEventId })
              : new Event(art);
            var h = STANDARD[art] ? self['on' + art] : null;
            if (typeof h === 'function') { try { h.call(self, kopie); } catch (x) { setTimeout(function () { throw x; }); } }
            self.dispatchEvent(kopie);
          });
        }
      }
      [['CONNECTING', 0], ['OPEN', 1], ['CLOSED', 2]].forEach(function (k) {
        KaiEreignisstrom[k[0]] = k[1]; KaiEreignisstrom.prototype[k[0]] = k[1];
      });
      KaiEreignisstrom.__kaiApp = true;
      window.EventSource = KaiEreignisstrom;
      document.addEventListener('visibilitychange', function () {
        alle.slice().forEach(function (q) { if (sichtbar()) q._verbinden(); else q._trennen(); });
      });
    })();
    """
}

extension WebSteuerung: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, let schema = url.scheme?.lowercased() else { return .allow }
        // Telefon, E-Mail, SMS, Karten → die passende App des iPhones (z. B. aus der Telefonliste).
        if ["tel", "telprompt", "mailto", "sms", "maps", "facetime"].contains(schema) {
            await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        fehler = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        einmalFertig = true
        anmeldungGeaendert?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fehlgeschlagen(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fehlgeschlagen(error)
    }

    private func fehlgeschlagen(_ error: Error) {
        let e = error as NSError
        // abgebrochen (z. B. weil gleich die nächste Seite kam) bzw. an eine andere App übergeben
        if e.domain == NSURLErrorDomain, e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain", e.code == 102 { return }
        fehler = "Keine Verbindung zu KAI (\(umgebung.host)). \(e.localizedDescription)"
    }

    /// Links mit neuem Fenster (`target=_blank`, `window.open`) in derselben Ansicht öffnen.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.absoluteString != "about:blank" {
            webView.load(navigationAction.request)
        }
        return nil
    }

    /// Mikrofon (KI-Chat: Spracheingabe) und Kamera für Seiten aus KAI selbst freigeben — die Erlaubnis des iPhones
    /// fragt iOS beim ersten Mal ab. Fremde Seiten (z. B. unter „Portale“) fragen wie im Browser selbst nach.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host.lowercased() == umgebung.host.lowercased() ? .grant : .prompt)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        await Dialog.hinweis(message)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await Dialog.frage(message)
    }
}

/// Hält die Steuerung nur schwach fest (sonst behielte die WebView ihre Steuerung für immer).
@MainActor
private final class SchwacherBote: NSObject, WKScriptMessageHandler {
    weak var ziel: WebSteuerung?
    init(_ ziel: WebSteuerung) { self.ziel = ziel }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        ziel?.nachricht(message.body)
    }
}

/// Einfache Meldungen der KAI-Seite (`alert`/`confirm`) als iPhone-Dialog.
@MainActor
enum Dialog {
    static func hinweis(_ text: String) async {
        await withCheckedContinuation { (fertig: CheckedContinuation<Void, Never>) in
            let a = UIAlertController(title: nil, message: text, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in fertig.resume() })
            guard zeigen(a) else { fertig.resume(); return }
        }
    }

    static func frage(_ text: String) async -> Bool {
        await withCheckedContinuation { fertig in
            let a = UIAlertController(title: nil, message: text, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Abbrechen", style: .cancel) { _ in fertig.resume(returning: false) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in fertig.resume(returning: true) })
            guard zeigen(a) else { fertig.resume(returning: false); return }
        }
    }

    private static func zeigen(_ a: UIAlertController) -> Bool {
        let szenen = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var oben = szenen.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return false }
        while let weiter = oben.presentedViewController { oben = weiter }
        oben.present(a, animated: true)
        return true
    }
}
