import SwiftUI
import WebKit

/// Rahmen für die WKWebView einer `WebSteuerung`. Die WebView lebt in der Steuerung weiter; der Rahmen hängt sie nur ein.
/// Dieselbe Seite kann an mehreren Orten vorkommen (z. B. Informationen unten als Reiter, unter „Mehr“ und über die Kachel auf
/// Start; ein Bereich über „Mehr“ und über Start) — eine UIView hat aber genau EINEN Platz. Sie hängt deshalb immer in dem Rahmen,
/// der zuletzt ins Fenster gekommen ist, also in dem, der gerade auf dem Bildschirm steht (UIKit nimmt Reiter, die nicht gewählt
/// sind, und Seiten, über die eine andere geschoben wurde, aus dem Fenster). Ein Rahmen außerhalb des Fensters nimmt sie nie an
/// sich, und ein Rahmen, der abgebaut wird, gibt sie nur frei, wenn sie noch bei ihm hängt.
final class WebRahmen: UIView {
    weak var steuerung: WebSteuerung?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { einhaengen() }
    }

    /// Hängt die Seite hier ein — nur wenn dieser Rahmen im Fenster ist.
    func einhaengen() {
        guard window != nil, let web = steuerung?.webView, web.superview !== self else { return }
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: leadingAnchor),
            web.trailingAnchor.constraint(equalTo: trailingAnchor),
            web.topAnchor.constraint(equalTo: topAnchor),
            web.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Gibt die Seite frei, wenn sie noch hier hängt (sonst hängt sie schon im sichtbaren Rahmen und bleibt dort).
    func freigeben() {
        if let web = steuerung?.webView, web.superview === self { web.removeFromSuperview() }
    }
}

/// Zeigt die WKWebView einer `WebSteuerung` in einem `WebRahmen`.
struct WebAnsicht: UIViewRepresentable {
    let steuerung: WebSteuerung

    func makeUIView(context: Context) -> WebRahmen {
        let rahmen = WebRahmen()
        rahmen.backgroundColor = UIColor(Farbe.hintergrund)
        rahmen.steuerung = steuerung
        rahmen.einhaengen()
        return rahmen
    }

    func updateUIView(_ rahmen: WebRahmen, context: Context) {
        guard rahmen.steuerung !== steuerung else { return }
        rahmen.freigeben()
        rahmen.steuerung = steuerung
        rahmen.einhaengen()
    }

    static func dismantleUIView(_ rahmen: WebRahmen, coordinator: ()) {
        rahmen.freigeben()
    }
}

/// Schmale Kopfleiste über einer KAI-Seite: nur Name und Umgebung (Peter 2026-11-27: Zurück, Haus und Neu laden taten sichtbar
/// nichts — wie auf dem iPhone üblich: neu laden durch Herunterziehen, zum Anfang durch nochmaliges Tippen auf den Reiter unten,
/// zurück über „← Zur Liste“ in KAI). Zurück ging nie: KAI trägt das Öffnen eines Datensatzes nicht in den Verlauf ein.
struct WebKopf: View {
    @ObservedObject var steuerung: WebSteuerung
    let titel: String

    var body: some View {
        HStack(spacing: 10) {
            Text(titel).font(.headline).lineLimit(1)
            UmgebungsKennzeichen(umgebung: steuerung.umgebung)
            Spacer()
            if steuerung.laedt { ProgressView().controlSize(.small) }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Farbe.flaeche)
        .overlay(alignment: .bottom) { Farbe.rand.frame(height: 1) }
    }
}

/// KAI-Seite mit Kopfleiste und Fehleranzeige.
struct KaiSeite: View {
    @ObservedObject var steuerung: WebSteuerung
    let titel: String
    /// Ohne eigene Kopfleiste, wenn die Navigation des iPhones schon einen Kopf zeigt (Informationen).
    var mitKopf = true

    var body: some View {
        VStack(spacing: 0) {
            if mitKopf { WebKopf(steuerung: steuerung, titel: titel) }
            ZStack {
                WebAnsicht(steuerung: steuerung)
                if let fehler = steuerung.fehler {
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(Farbe.rotText)
                        Text(fehler).multilineTextAlignment(.center).foregroundStyle(Farbe.text)
                        Button("Erneut versuchen") { steuerung.neuLaden() }.buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Farbe.hintergrund)
                }
            }
        }
        .background(Farbe.hintergrund)
        .onAppear { steuerung.erstmalsLaden() }
        // Vor dem Neuladen (Herunterziehen, Reiter nochmal tippen): gleicher Wortlaut wie in KAI (ungespeichert.js)
        .alert("Ungespeicherte Änderungen", isPresented: Binding(get: { steuerung.rueckfrage != nil },
                                                                 set: { if !$0 { steuerung.rueckfrage = nil } }),
               presenting: steuerung.rueckfrage) { r in
            Button("Verwerfen", role: .destructive) { steuerung.rueckfrage = nil; r.weiter() }
            Button("Weiter bearbeiten", role: .cancel) { steuerung.rueckfrage = nil; r.abbruch?() }
        } message: { _ in
            Text("Es gibt ungespeicherte Änderungen. Verwerfen und neu laden?")
        }
    }
}

/// Reiter unten für einen Bereich mit KAI-Ansicht (Dienstanweisung, Meldungen, Asset Manager, Schiffstatus,
/// KI-Chat): die KAI-Seite mit schmaler Kopfleiste. Was die Person dort sehen darf, prüft KAI selbst.
struct KaiBereichReiter: View {
    @EnvironmentObject private var app: AppZustand
    let bereich: Bereich

    var body: some View {
        if let seite = app.seite(bereich) {
            KaiSeite(steuerung: seite, titel: bereich.name).id(ObjectIdentifier(seite))
        }
    }
}

/// Reiter „Anmelden“: solange die App die Rechte nicht kennt, die KAI-Anmeldeseite. Nach der Anmeldung liest die App die
/// Rechte aus KAI und zeigt die Reiter der Person.
struct AnmeldeReiter: View {
    @EnvironmentObject private var app: AppZustand

    var body: some View {
        if let seite = app.anmeldung {
            KaiSeite(steuerung: seite, titel: "Anmelden").id(ObjectIdentifier(seite))
        }
    }
}

/// Eine KAI-Seite unter „Mehr“ (Bereich, der nicht unten steht, bzw. Benachrichtigungen = #benachrichtigungen,
/// Mein Konto = #profil): ohne eigene Kopfleiste, den Kopf hat die Navigation des iPhones.
struct MehrKaiSeite: View {
    @ObservedObject var steuerung: WebSteuerung
    let titel: String
    /// Ansicht, die beim Öffnen gezeigt wird (nur bei der gemeinsamen Seite für Benachrichtigungen/Konto).
    var ansicht: String?

    var body: some View {
        KaiSeite(steuerung: steuerung, titel: titel, mitKopf: false)
            .onAppear { if let ansicht { steuerung.zeigen(ansicht) } }
            .navigationTitle(titel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if steuerung.laedt { ProgressView().controlSize(.small) }
                }
            }
    }
}
