import SwiftUI
import AVFoundation

@main
struct KAIBSBApp: App {
    @StateObject private var app = AppZustand()

    init() {
        // Vorlesen im KI-Chat auch bei stumm geschaltetem iPhone hörbar, ohne laufende Musik anderer Apps abzubrechen.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if app.umgebung == nil {
                    EinrichtungAnsicht()
                } else {
                    HauptAnsicht()
                }
            }
            .environmentObject(app)
            .tint(Farbe.primaer)
        }
    }
}

/// Unten fünf Reiter: drei KAI-Seiten, Scannen, und „Mehr“ (Drucken, Einstellungen).
struct HauptAnsicht: View {
    @EnvironmentObject private var app: AppZustand

    var body: some View {
        TabView(selection: $app.reiter) {
            AssetManagerReiter()
                .tabItem { Label("Asset Manager", systemImage: "server.rack") }
                .tag(Reiter.assetManager)
            InformationenReiter()
                .tabItem { Label("Informationen", systemImage: "info.circle") }
                .tag(Reiter.informationen)
            KIReiter()
                .tabItem { Label("KI", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(Reiter.ki)
            ScanAnsicht()
                .tabItem { Label("Scannen", systemImage: "qrcode.viewfinder") }
                .tag(Reiter.scannen)
            MehrReiter()
                .tabItem { Label("Mehr", systemImage: "ellipsis.circle") }
                .tag(Reiter.mehr)
        }
    }
}

/// „Mehr“: Benachrichtigungen und Konto (aus KAI), Etikett drucken, Einstellungen.
struct MehrReiter: View {
    @EnvironmentObject private var app: AppZustand

    var body: some View {
        NavigationStack(path: $app.mehrPfad) {
            List {
                Section {
                    NavigationLink(value: MehrZiel.benachrichtigungen) {
                        Label { Text("Benachrichtigungen") } icon: { Image(systemName: "bell").foregroundStyle(Farbe.primaer) }
                    }
                    NavigationLink(value: MehrZiel.konto) {
                        Label { Text("Mein Konto") } icon: { Image(systemName: "person.crop.circle").foregroundStyle(Farbe.primaer) }
                    }
                } footer: {
                    Text("Aus KAI — mit deiner Anmeldung.")
                }
                NavigationLink(value: MehrZiel.drucken) {
                    Label { Text("Etikett drucken") } icon: { Image(systemName: "printer").foregroundStyle(Farbe.primaer) }
                }
                NavigationLink(value: MehrZiel.einstellungen) {
                    Label { Text("Einstellungen") } icon: { Image(systemName: "gearshape").foregroundStyle(Farbe.primaer) }
                }
            }
            .navigationTitle("Mehr")
            .toolbar {
                if let u = app.umgebung {
                    ToolbarItem(placement: .topBarTrailing) { UmgebungsKennzeichen(umgebung: u) }
                }
            }
            .navigationDestination(for: MehrZiel.self) { ziel in
                switch ziel {
                case .benachrichtigungen: MehrKaiSeite(titel: "Benachrichtigungen", ansicht: "benachrichtigungen")
                case .konto: MehrKaiSeite(titel: "Mein Konto", ansicht: "profil")
                case .drucken: DruckAnsicht()
                case .einstellungen: EinstellungenAnsicht()
                }
            }
        }
    }
}

/// Erster Start: mit welcher KAI-Umgebung verbinden?
struct EinrichtungAnsicht: View {
    @EnvironmentObject private var app: AppZustand
    @State private var wahl = Umgebung.vorgabe

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image("KAIZeichen")
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("KAI BSB").font(.title.bold())
                        Text("Kurs-, Auftrags- & Informationssystem").font(.subheadline).foregroundStyle(Farbe.textLeise)
                    }
                }
                .padding(.top, 24)

                Text("Mit welcher KAI-Umgebung soll sich die App verbinden?")
                    .font(.headline)

                VStack(spacing: 10) {
                    ForEach(Umgebung.allCases) { u in
                        Button { wahl = u } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: wahl == u ? "largecircle.fill.circle" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(wahl == u ? Farbe.primaer : Farbe.textLeise)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(u.name).font(.body.weight(.semibold))
                                        UmgebungsKennzeichen(umgebung: u)
                                    }
                                    Text(u.adresse).font(.footnote.monospaced()).foregroundStyle(Farbe.textLeise)
                                    Text(u.beschreibung).font(.footnote).foregroundStyle(Farbe.textLeise)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(wahl == u ? Farbe.primaer : Farbe.rand, lineWidth: wahl == u ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Farbe.text)
                    }
                }

                Text("Danach meldest du dich auf der normalen KAI-Anmeldeseite an — mit Kennwort, zweitem Faktor oder Microsoft, wie im Browser. Die App bleibt angemeldet. Die Umgebung kannst du später in den Einstellungen ändern.")
                    .font(.footnote)
                    .foregroundStyle(Farbe.textLeise)

                Button { app.verbinden(wahl) } label: {
                    Text("Verbinden").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .background(Farbe.hintergrund.ignoresSafeArea())
    }
}

/// Eine KAI-Ansicht unter „Mehr“ (Benachrichtigungen = #benachrichtigungen, Mein Konto = #profil).
struct MehrKaiSeite: View {
    @EnvironmentObject private var app: AppZustand
    let titel: String
    let ansicht: String

    var body: some View {
        Group {
            if let seite = app.mehrSeite {
                KaiSeite(steuerung: seite, titel: titel, mitKopf: false)
                    .onAppear { seite.zeigen(ansicht) }
            }
        }
        .navigationTitle(titel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let seite = app.mehrSeite {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { seite.neuLaden() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Neu laden")
                }
            }
        }
        .background(Farbe.hintergrund)
    }
}
