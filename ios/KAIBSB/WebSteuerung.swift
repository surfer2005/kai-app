import SwiftUI
import UIKit
import WebKit

/// Eine KAI-Seite in der App (Asset Manager bzw. Informationen). Beide teilen sich den Website-Speicher des iPhones:
/// die Anmeldung (Token `lpv_token` im localStorage, wie im Browser) gilt in beiden und bleibt nach dem Schließen erhalten.
@MainActor
final class WebSteuerung: NSObject, ObservableObject {
    @Published private(set) var kannZurueck = false
    @Published private(set) var laedt = false
    @Published private(set) var fehler: String?

    let webView: WKWebView
    let umgebung: Umgebung
    let startAnsicht: String
    /// Meldet, wenn in der KAI-Seite ein Gerät geöffnet wurde (id, Name) — für den Reiter „Drucken“.
    var geraetGeoeffnet: ((Int, String?) -> Void)?

    private var beobachter: [NSKeyValueObservation] = []
    private var geladen = false

    init(umgebung: Umgebung, startAnsicht: String) {
        self.umgebung = umgebung
        self.startAnsicht = startAnsicht
        let konfiguration = WKWebViewConfiguration()
        konfiguration.websiteDataStore = .default()
        konfiguration.applicationNameForUserAgent = "KAI-BSB-App/\(AppInfo.version)"
        konfiguration.allowsInlineMediaPlayback = true
        let inhalt = WKUserContentController()
        inhalt.addUserScript(WKUserScript(source: Self.beobachterSkript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        konfiguration.userContentController = inhalt
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

    /// Token der Anmeldung aus dem localStorage der KAI-Seite (leer = nicht angemeldet).
    func token() async -> String? {
        guard umgebung.enthaelt(webView.url) else { return nil }
        let wert: String = await withCheckedContinuation { fertig in
            webView.evaluateJavaScript("(function(){ try { return localStorage.getItem('lpv_token') || '' } catch (e) { return '' } })()") { ergebnis, _ in
                fertig.resume(returning: (ergebnis as? String) ?? "")
            }
        }
        return wert.isEmpty || wert == "offline" ? nil : wert
    }

    /// Abmelden wie in KAI: Token entfernen und die Seite neu laden (zeigt dann die Anmeldung).
    func abmelden() async {
        guard umgebung.enthaelt(webView.url) else { return }
        _ = await withCheckedContinuation { (fertig: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript("try { localStorage.removeItem('lpv_token') } catch (e) {}; null") { _, _ in fertig.resume() }
        }
        zurStartansicht()
    }

    fileprivate func nachricht(_ inhalt: Any) {
        guard let d = inhalt as? [String: Any], d["art"] as? String == "geraet" else { return }
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
    static let beobachterSkript = """
    (function () {
      if (window.__kaiApp) return; window.__kaiApp = true;
      var melden = function (d) { try { window.webkit.messageHandlers.kaiApp.postMessage(d) } catch (e) {} };
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
