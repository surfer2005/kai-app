import SwiftUI
import WebKit

/// Zeigt die WKWebView einer `WebSteuerung`. Die WebView lebt in der Steuerung weiter; diese Ansicht hängt sie nur ein
/// (in einen eigenen Rahmen, damit sie beim Wechsel zwischen Ansichten nicht aus dem falschen Rahmen gelöst wird).
struct WebAnsicht: UIViewRepresentable {
    @ObservedObject var steuerung: WebSteuerung

    func makeUIView(context: Context) -> UIView {
        let rahmen = UIView()
        rahmen.backgroundColor = UIColor(Farbe.hintergrund)
        einhaengen(in: rahmen)
        return rahmen
    }

    func updateUIView(_ rahmen: UIView, context: Context) {
        if steuerung.webView.superview !== rahmen { einhaengen(in: rahmen) }
    }

    static func dismantleUIView(_ rahmen: UIView, coordinator: ()) {
        for ansicht in rahmen.subviews where ansicht is WKWebView { ansicht.removeFromSuperview() }
    }

    private func einhaengen(in rahmen: UIView) {
        let web = steuerung.webView
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        rahmen.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: rahmen.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: rahmen.trailingAnchor),
            web.topAnchor.constraint(equalTo: rahmen.topAnchor),
            web.bottomAnchor.constraint(equalTo: rahmen.bottomAnchor),
        ])
    }
}

/// Schmale Kopfleiste über einer KAI-Seite: zurück, Name, Umgebung, Start, neu laden.
struct WebKopf: View {
    @ObservedObject var steuerung: WebSteuerung
    let titel: String

    var body: some View {
        HStack(spacing: 10) {
            Button { steuerung.zurueck() } label: { Image(systemName: "chevron.left") }
                .disabled(!steuerung.kannZurueck)
                .accessibilityLabel("Zurück")
            Text(titel).font(.headline).lineLimit(1)
            UmgebungsKennzeichen(umgebung: steuerung.umgebung)
            Spacer()
            if steuerung.laedt { ProgressView().controlSize(.small) }
            Button { steuerung.zurStartansicht() } label: { Image(systemName: "house") }
                .accessibilityLabel("Zur Startansicht")
            Button { steuerung.neuLaden() } label: { Image(systemName: "arrow.clockwise") }
                .accessibilityLabel("Neu laden")
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
    }
}

/// Reiter unten für einen Bereich mit KAI-Ansicht (Dienstanweisung, Meldungen, Störmeldedienst, Asset Manager, Schiffstatus,
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
                    Button { steuerung.zurueck() } label: { Image(systemName: "chevron.backward.circle") }
                        .disabled(!steuerung.kannZurueck)
                        .accessibilityLabel("Zurück in der Seite")
                    Button { steuerung.neuLaden() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Neu laden")
                }
            }
    }
}
