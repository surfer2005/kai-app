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

/// Die Leiste unten (Klick-Dummy „KAI-App“): links fest „Start“, dahinter bis zu drei Bereiche der Person (aus ihren Rechten in KAI,
/// selbst wählbar unter Mehr → Leiste anpassen), rechts fest „Mehr“ mit den übrigen Bereichen. Kein Burger-Menü.
struct HauptAnsicht: View {
    @EnvironmentObject private var app: AppZustand
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView(selection: $app.reiter) {
            StartReiter()
                .tabItem { Label("Start", systemImage: "house") }
                .tag(Reiter.start)
            ForEach(app.rechte == nil ? [] : app.leiste.unten) { b in
                BereichReiter(bereich: b)
                    .tabItem { Label(b.leistenName, systemImage: b.symbol) }
                    .tag(Reiter.bereich(b))
            }
            MehrReiter()
                .tabItem { Label("Mehr", systemImage: "ellipsis.circle") }
                .tag(Reiter.mehr)
        }
        // Zurück in die App: Rechte neu lesen (in KAI geändert, inzwischen abgemeldet …)
        .onChange(of: phase) { _, neu in if neu == .active { app.rechtePruefen() } }
    }
}

/// Reiter „Start“: die KAI-Startseite in App-Darstellung (Begrüßung, Hinweis, „In der App“ — AppStart.vue in KAI); ohne Anmeldung
/// zeigt KAI dort die Anmeldeseite. Ohne eigene Kopfleiste — Glocke und Kürzel stehen in der Seite.
struct StartReiter: View {
    @EnvironmentObject private var app: AppZustand

    var body: some View {
        if let seite = app.anmeldung {
            KaiSeite(steuerung: seite, titel: "Start", mitKopf: false).id(ObjectIdentifier(seite))
                .onAppear { seite.startansichtZeigen() }
        }
    }
}

/// Ein Bereich als Reiter unten.
struct BereichReiter: View {
    let bereich: Bereich

    var body: some View {
        switch bereich {
        case .scannen: ScanReiter()
        case .informationen: InformationenReiter()
        default: KaiBereichReiter(bereich: bereich)
        }
    }
}

/// Ein Bereich unter „Mehr“ (in dessen Navigation).
struct BereichInMehr: View {
    @EnvironmentObject private var app: AppZustand
    let bereich: Bereich

    var body: some View {
        switch bereich {
        case .scannen: ScanAnsicht()
        case .informationen: InformationenListe()
        default:
            if let seite = app.seite(bereich) {
                MehrKaiSeite(steuerung: seite, titel: bereich.name)
            }
        }
    }
}

/// „Mehr“: die Bereiche, die nicht unten stehen, Benachrichtigungen und Konto (aus KAI), Leiste anpassen, Etikett drucken, Einstellungen.
struct MehrReiter: View {
    @EnvironmentObject private var app: AppZustand

    var body: some View {
        NavigationStack(path: $app.mehrPfad) {
            List {
                if app.rechte != nil, !app.leiste.mehr.isEmpty {
                    Section("Weitere Bereiche") {
                        ForEach(app.leiste.mehr) { b in
                            NavigationLink(value: MehrZiel.bereich(b)) {
                                Label { Text(b.name) } icon: { Image(systemName: b.symbol).foregroundStyle(Farbe.primaer) }
                            }
                        }
                    }
                }
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
                Section {
                    if app.rechte != nil {
                        NavigationLink(value: MehrZiel.leiste) {
                            Label { Text("Leiste anpassen") } icon: { Image(systemName: "dock.rectangle").foregroundStyle(Farbe.primaer) }
                        }
                    }
                    if app.darf(.assetManager) {
                        NavigationLink(value: MehrZiel.drucken) {
                            Label { Text("Etikett drucken") } icon: { Image(systemName: "printer").foregroundStyle(Farbe.primaer) }
                        }
                    }
                    NavigationLink(value: MehrZiel.einstellungen) {
                        Label { Text("Einstellungen") } icon: { Image(systemName: "gearshape").foregroundStyle(Farbe.primaer) }
                    }
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
                case .bereich(let b): BereichInMehr(bereich: b)
                case .benachrichtigungen: MehrSeiteAusKai(titel: "Benachrichtigungen", ansicht: "benachrichtigungen")
                case .konto: MehrSeiteAusKai(titel: "Mein Konto", ansicht: "profil")
                case .leiste: LeisteAnpassenAnsicht()
                case .drucken: DruckAnsicht()
                case .einstellungen: EinstellungenAnsicht()
                }
            }
        }
    }
}

/// Benachrichtigungen (#benachrichtigungen) bzw. Mein Konto (#profil) — eine gemeinsame KAI-Seite unter „Mehr“.
struct MehrSeiteAusKai: View {
    @EnvironmentObject private var app: AppZustand
    let titel: String
    let ansicht: String

    var body: some View {
        if let seite = app.mehrSeite {
            MehrKaiSeite(steuerung: seite, titel: titel, ansicht: ansicht)
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
