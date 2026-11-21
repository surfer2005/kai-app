import SwiftUI

/// Die Punkte des Infocenters — Schlüssel und Namen wie in KAI (`client/src/App.vue`, NAV_GROUPS → informationen → infocenter).
struct InfoPunkt: Identifiable, Hashable {
    let schluessel: String
    let name: String
    let symbol: String
    var id: String { schluessel }

    static let alle: [InfoPunkt] = [
        InfoPunkt(schluessel: "zielanzeiger", name: "Zielanzeiger", symbol: "signpost.right"),
        InfoPunkt(schluessel: "shipmap", name: "GPS-Karte · Schiffe", symbol: "ferry"),
        InfoPunkt(schluessel: "infowetter", name: "Wetter", symbol: "cloud.sun"),
        InfoPunkt(schluessel: "telefonnummern", name: "Telefonnummern", symbol: "phone"),
        InfoPunkt(schluessel: "schiffseinsatzplan", name: "Schiffseinsatzplan", symbol: "calendar"),
        InfoPunkt(schluessel: "dienstplan", name: "Dienstplan", symbol: "list.clipboard"),
        InfoPunkt(schluessel: "charteruebersicht", name: "Charterübersicht", symbol: "sailboat"),
        InfoPunkt(schluessel: "cateringuebersicht", name: "Cateringübersicht", symbol: "fork.knife"),
        InfoPunkt(schluessel: "bereitschaftsplan", name: "Bereitschaftsplan", symbol: "person.badge.clock"),
        InfoPunkt(schluessel: "portale", name: "Portale", symbol: "square.grid.2x2"),
    ]
}

/// Reiter „Informationen“: die Punkte des Infocenters als Liste, jeder öffnet die KAI-Ansicht.
/// Was du in KAI nicht sehen darfst, zeigt KAI auch hier nicht.
struct InformationenReiter: View {
    @EnvironmentObject private var app: AppZustand
    @State private var pfad: [InfoPunkt] = []

    var body: some View {
        NavigationStack(path: $pfad) {
            List {
                Section {
                    ForEach(InfoPunkt.alle) { punkt in
                        NavigationLink(value: punkt) {
                            Label { Text(punkt.name) } icon: { Image(systemName: punkt.symbol).foregroundStyle(Farbe.primaer) }
                        }
                    }
                } footer: {
                    Text("Die Ansichten kommen direkt aus KAI — mit deiner Anmeldung und deinen Rechten.")
                }
            }
            .navigationTitle("Informationen")
            .toolbar {
                if let u = app.umgebung {
                    ToolbarItem(placement: .topBarTrailing) { UmgebungsKennzeichen(umgebung: u) }
                }
            }
            .navigationDestination(for: InfoPunkt.self) { punkt in
                InfoSeite(punkt: punkt)
            }
        }
    }
}

struct InfoSeite: View {
    @EnvironmentObject private var app: AppZustand
    let punkt: InfoPunkt

    var body: some View {
        Group {
            if let seite = app.informationen {
                KaiSeite(steuerung: seite, titel: punkt.name, mitKopf: false)
                    .onAppear { seite.zeigen(punkt.schluessel) }
            }
        }
        .navigationTitle(punkt.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let seite = app.informationen {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { seite.neuLaden() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Neu laden")
                }
            }
        }
        .background(Farbe.hintergrund)
    }
}
