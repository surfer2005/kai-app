import SwiftUI
import AVFoundation

/// Reiter „Scannen“ (unten): eigene Navigation um die Scan-Ansicht. Unter „Mehr“ steht die Scan-Ansicht in dessen Navigation.
struct ScanReiter: View {
    var body: some View {
        NavigationStack { ScanAnsicht() }
    }
}

/// „Scannen“: QR-Code oder Barcode lesen → Gerät im Asset Manager öffnen. Geht auch ohne Kamera über die Eingabe.
struct ScanAnsicht: View {
    @EnvironmentObject private var app: AppZustand
    @State private var kameraErlaubt = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var sichtbar = false
    @State private var eingabe = ""
    @State private var zustand: ScanZustand = .bereit
    @State private var arbeitet = false

    var body: some View {
        Group {
            VStack(spacing: 0) {
                kamera
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipped()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            TextField("Gerätename, Inventarnummer oder Adresse", text: $eingabe)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit { verarbeiten(eingabe) }
                                .padding(10)
                                .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Farbe.rand))
                            Button("Suchen") { verarbeiten(eingabe) }
                                .buttonStyle(.borderedProminent)
                                .disabled(eingabe.trimmingCharacters(in: .whitespaces).isEmpty || arbeitet)
                        }
                        if arbeitet { ProgressView("Suche in KAI …") }
                        ergebnis
                    }
                    .padding(16)
                }
            }
            .background(Farbe.hintergrund)
            .navigationTitle("Scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let u = app.umgebung {
                    ToolbarItem(placement: .topBarTrailing) { UmgebungsKennzeichen(umgebung: u) }
                }
            }
        }
        .onAppear {
            sichtbar = true
            if kameraErlaubt == .notDetermined, KameraAnsicht.verfuegbar {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    DispatchQueue.main.async { kameraErlaubt = AVCaptureDevice.authorizationStatus(for: .video) }
                }
            }
        }
        .onDisappear { sichtbar = false }
    }

    @ViewBuilder private var kamera: some View {
        if !KameraAnsicht.verfuegbar {
            platzhalter("camera.metering.unknown", "Keine Kamera verfügbar (z. B. im Simulator). Gib den Code unten ein.")
        } else if kameraErlaubt == .authorized {
            ZStack(alignment: .bottom) {
                KameraAnsicht(aktiv: sichtbar && app.zeigt(.scannen)) { text in verarbeiten(text) }
                Text("Etikett in den Rahmen halten")
                    .font(.footnote)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        } else if kameraErlaubt == .notDetermined {
            platzhalter("camera", "Kamera wird vorbereitet …")
        } else {
            VStack(spacing: 10) {
                platzhalter("camera.badge.ellipsis", "Die App darf die Kamera nicht benutzen.")
                Button("In den iPhone-Einstellungen erlauben") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
    }

    private func platzhalter(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle)
            Text(text).multilineTextAlignment(.center).font(.subheadline)
        }
        .foregroundStyle(Farbe.textLeise)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Farbe.flaeche2)
    }

    @ViewBuilder private var ergebnis: some View {
        switch zustand {
        case .bereit:
            Text("Scanne das QR-Etikett eines Geräts (aus KAI oder dem alten Asset Manager) oder einen Barcode mit Gerätename bzw. Seriennummer. Gefundene Geräte öffnen sich im Asset Manager.")
                .font(.footnote)
                .foregroundStyle(Farbe.textLeise)
        case let .hinweis(text, ton):
            Hinweis(ton: ton, symbol: ton == .rot ? "exclamationmark.triangle" : "info.circle", text: text)
        case let .andereUmgebung(id, etikett):
            VStack(alignment: .leading, spacing: 10) {
                Hinweis(ton: .gelb, symbol: "exclamationmark.triangle",
                        text: "Dieses Etikett stammt aus KAI \(etikett.name). Verbunden bist du mit \(app.umgebung?.name ?? "—"). Die Gerätenummer \(id) kann dort ein anderes Gerät sein.")
                Button("Trotzdem hier öffnen") { app.geraetOeffnen(id) }.buttonStyle(.bordered)
            }
        case let .gelesen(text, url):
            VStack(alignment: .leading, spacing: 10) {
                Text("Kein Geräte-Etikett. Gelesen:").font(.subheadline.weight(.semibold))
                Text(text).font(.callout.monospaced()).textSelection(.enabled)
                HStack {
                    Button("Kopieren") { UIPasteboard.general.string = text }.buttonStyle(.bordered)
                    if let url { Button("Im Browser öffnen") { UIApplication.shared.open(url) }.buttonStyle(.bordered) }
                }
            }
        case let .auswahl(begriff, treffer):
            VStack(alignment: .leading, spacing: 8) {
                Text("\(treffer.count) Geräte passen zu „\(begriff)“:").font(.subheadline.weight(.semibold))
                ForEach(treffer) { g in
                    Button { app.geraetOeffnen(g.id, name: g.name) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.anzeigename).font(.body.weight(.semibold))
                            if !g.zusatz.isEmpty { Text(g.zusatz).font(.footnote).foregroundStyle(Farbe.textLeise) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func verarbeiten(_ text: String) {
        let roh = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roh.isEmpty, !arbeitet, let umgebung = app.umgebung else { return }
        eingabe = roh
        switch ScanAuswertung.erkennen(roh) {
        case let .kaiGeraet(id, etikett):
            if let etikett, etikett != umgebung {
                zustand = .andereUmgebung(id: id, etikett: etikett)
            } else {
                zustand = .hinweis("Gerät \(id) wird im Asset Manager geöffnet.", .gruen)
                app.geraetOeffnen(id)
            }
        case let .altesGeraet(altId):
            arbeiten {
                if let id = try await KaiApi(umgebung: umgebung, token: nil).altesGeraetAufloesen(altId) {
                    zustand = .hinweis("Altes Etikett \(altId) → Gerät \(id), wird im Asset Manager geöffnet.", .gruen)
                    app.geraetOeffnen(id)
                } else {
                    zustand = .hinweis("Zum alten Etikett \(altId) kennt KAI kein Gerät.", .gelb)
                }
            }
        case let .suchbegriff(begriff):
            arbeiten {
                guard let api = await app.api() else { return }
                let treffer = try await api.geraeteSuchen(begriff)
                if let g = ScanAuswertung.bester(treffer, fuer: begriff) {
                    zustand = .hinweis("\(g.anzeigename) wird im Asset Manager geöffnet.", .gruen)
                    app.geraetOeffnen(g.id, name: g.name)
                } else if treffer.isEmpty {
                    zustand = .hinweis("Kein Gerät „\(begriff)“ im Asset Manager gefunden.", .gelb)
                } else {
                    zustand = .auswahl(begriff: begriff, treffer: treffer)
                }
            }
        case let .link(url):
            zustand = .gelesen(text: roh, url: url)
        case let .text(t):
            zustand = .gelesen(text: t, url: nil)
        }
    }

    private func arbeiten(_ aufgabe: @escaping () async throws -> Void) {
        arbeitet = true
        Task {
            do { try await aufgabe() } catch { zustand = .hinweis(error.localizedDescription, .rot) }
            arbeitet = false
        }
    }
}

enum ScanZustand {
    case bereit
    case hinweis(String, Hinweis.Ton)
    case andereUmgebung(id: Int, etikett: Umgebung)
    case gelesen(text: String, url: URL?)
    case auswahl(begriff: String, treffer: [GeraetKurz])
}
