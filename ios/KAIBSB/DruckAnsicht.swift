import SwiftUI

/// „Mehr“ → „Etikett drucken“: Etikett des zuletzt geöffneten Geräts auf dem Brother-Etikettendrucker.
struct DruckAnsicht: View {
    @EnvironmentObject private var app: AppZustand
    @AppStorage("drucker") private var druckerWahl = DruckerModell.ptP710BT.rawValue
    @AppStorage("band") private var band = 24
    @AppStorage("laenge") private var laenge = 40
    @AppStorage("druckerIP") private var druckerIP = ""
    @AppStorage("druckerSerie") private var druckerSerie = ""
    @State private var keinDrucker = false

    @State private var geraet: GeraetKurz?
    @State private var laedt = false
    @State private var meldung: (text: String, ton: Hinweis.Ton)?
    @State private var druckt = false

    private var modell: DruckerModell { DruckerModell(rawValue: druckerWahl) ?? .ptP710BT }
    private var masse: EtikettMasse { EtikettMasse.berechnen(band: band, laenge: laenge) }

    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !DruckDienst.bausteinVorhanden {
                        Hinweis(ton: .gelb, symbol: "puzzlepiece.extension",
                                text: "Drucker-Baustein fehlt: In dieser Fassung ist das Brother-SDK nicht eingebunden. Die Vorschau geht, gedruckt wird erst mit dem Baustein (Anleitung: Ordner „Frameworks“).")
                    }
                    if app.offenesGeraet?.vorfuehrung == true {
                        Hinweis(ton: .gelb, symbol: "eye",
                                text: "Vorführung: Platzhalter-Etikett „MUSTER“, kein Gerät aus KAI.")
                    }
                    inhalt
                }
                .padding(16)
            }
            .background(Farbe.hintergrund)
            .navigationTitle("Etikett drucken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let u = app.umgebung {
                    ToolbarItem(placement: .topBarTrailing) { UmgebungsKennzeichen(umgebung: u) }
                }
            }
        }
        .task(id: app.offenesGeraet) { await laden() }
    }

    @ViewBuilder private var inhalt: some View {
        if let offen = app.offenesGeraet, let umgebung = app.umgebung {
            let name = geraet?.name ?? offen.name ?? "Gerät \(offen.id)"
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.title3.bold())
                if let g = geraet, !g.zusatz.isEmpty { Text(g.zusatz).font(.footnote).foregroundStyle(Farbe.textLeise) }
                if laedt { ProgressView().controlSize(.small) }
            }

            let bild = Etikett.bild(name: name, qrInhalt: umgebung.geraeteLink(offen.id), masse: masse)
            VStack(spacing: 8) {
                Image(uiImage: bild)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 170, maxHeight: 280)
                    .padding(8)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(Farbe.rand))
                Text("\(Int(masse.bandMm)) mm Band · \(Int(masse.laengeMm)) mm lang · QR: \(umgebung.geraeteLink(offen.id))")
                    .font(.caption)
                    .foregroundStyle(Farbe.textLeise)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Button {
                drucken(bild)
            } label: {
                HStack {
                    if druckt { ProgressView().tint(.white) }
                    Text(druckt ? "Wird gedruckt …" : "Auf \(modell.name) drucken (\(modell.verbindung))")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(druckt || offen.vorfuehrung)

            ShareLink(item: Image(uiImage: bild), preview: SharePreview(name, image: Image(uiImage: bild))) {
                Label("Etikett als Bild teilen", systemImage: "square.and.arrow.up")
            }

            if let meldung { Hinweis(ton: meldung.ton, symbol: meldung.ton == .gruen ? "checkmark.circle" : "exclamationmark.triangle", text: meldung.text) }
            if keinDrucker {
                // Drucker direkt hier koppeln (Auswahl von iOS) und gleich drucken
                Button {
                    Task {
                        if let fehler = await DruckDienst.druckerSuchen() { meldung = (fehler, .rot) }
                        else { drucken(bild) }
                    }
                } label: { Label("Drucker suchen (Bluetooth)", systemImage: "dot.radiowaves.left.and.right") }
                .buttonStyle(.bordered)
            }

            Text("Drucker, Bandbreite und Etikettenlänge stellst du unter „Mehr → Einstellungen“ ein.")
                .font(.footnote)
                .foregroundStyle(Farbe.textLeise)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "printer").font(.largeTitle).foregroundStyle(Farbe.primaer)
                Text("Noch kein Gerät gewählt").font(.title3.bold())
                Text("Öffne ein Gerät im Reiter „Asset Manager“ oder scanne sein Etikett — dann erscheint hier das Etikett zum Drucken.")
                    .foregroundStyle(Farbe.textLeise)
                HStack {
                    Button("Zum Asset Manager") { app.reiter = .assetManager }.buttonStyle(.bordered)
                    Button("Scannen") { app.reiter = .scannen }.buttonStyle(.bordered)
                }
            }
        }
    }

    /// Name und Angaben frisch aus KAI holen (mit dem Token der Anmeldung).
    private func laden() async {
        geraet = nil
        meldung = nil
        guard let offen = app.offenesGeraet, !offen.vorfuehrung, let api = await app.api() else { return }
        laedt = true
        defer { laedt = false }
        do {
            geraet = try await api.geraet(offen.id)
        } catch {
            meldung = (error.localizedDescription, .gelb)
        }
    }

    private func drucken(_ bild: UIImage) {
        druckt = true
        meldung = nil
        keinDrucker = false
        let modell = modell, band = band, ip = druckerIP, serie = druckerSerie
        Task {
            do {
                try await DruckDienst.drucken(bild, modell: modell, band: band, ip: ip, serie: serie)
                meldung = ("Etikett an \(modell.name) gesendet.", .gruen)
            } catch {
                meldung = (error.localizedDescription, .rot)
                if case DruckFehler.keinBluetoothDrucker = error { keinDrucker = true }
            }
            druckt = false
        }
    }
}
