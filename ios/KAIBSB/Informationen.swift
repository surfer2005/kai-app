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

/// Reiter „Informationen“ (unten): die Punkte des Infocenters als Kacheln, jede öffnet die KAI-Ansicht.
/// Was du in KAI nicht sehen darfst, zeigt KAI auch hier nicht.
struct InformationenReiter: View {
    var body: some View {
        NavigationStack { InformationenListe() }
    }
}

/// Die Punkte des Infocenters als Kacheln, zwei nebeneinander — wie die Kacheln auf Start (KAI: `zk zk-kai klick`, Peter 2026-11-24:
/// „Einheitlichkeit in einer App“; die frühere Liste steht bei cbd2e0f2). Unten als eigener Reiter, unter „Mehr“ oder über die
/// Kachel auf Start — überall dieselbe Ansicht in der Navigation des jeweiligen Reiters.
struct InformationenListe: View {
    @EnvironmentObject private var app: AppZustand
    private let spalten = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: spalten, alignment: .leading, spacing: 9) {
                    ForEach(InfoPunkt.alle) { punkt in
                        NavigationLink { InfoSeite(punkt: punkt) } label: { Kachel(symbol: punkt.symbol, name: punkt.name) }
                            .buttonStyle(.plain)
                    }
                }
                Text("Die Ansichten kommen direkt aus KAI — mit deiner Anmeldung und deinen Rechten.")
                    .font(.footnote)
                    .foregroundStyle(Farbe.textLeise)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Farbe.hintergrund)
        .navigationTitle("Informationen")
        .toolbar {
            if let u = app.umgebung {
                ToolbarItem(placement: .topBarTrailing) { UmgebungsKennzeichen(umgebung: u) }
            }
        }
    }
}

/// Eine Kachel wie in KAI (`client/src/styles/zustandskachel.css`, `.zk.zk-kai`): Fläche, 1 px Rand, Radius 10, grüner Streifen
/// links 5 px; Symbol oben links (grün), darunter der Name.
/// Alle Kacheln gleich groß (Peter 2026-11-27): der Name hält immer zwei Zeilen frei — vorher war eine Kachel mit einzeiligem Namen
/// („Wetter“) niedriger als eine mit zweizeiligem („GPS-Karte · Schiffe“). Braucht ein Name bei großer Schrift mehr, wird er kleiner
/// statt die Kachel höher.
struct Kachel: View {
    let symbol: String
    let name: String
    /// Feste Höhe für das Symbol: die SF-Symbole sind verschieden hoch (Besteck höher als Wolke), sonst wäre jede Zeile anders hoch.
    @ScaledMetric(relativeTo: .title2) private var symbolHoehe: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Farbe.primaer)
                .frame(width: symbolHoehe, height: symbolHoehe, alignment: .leading)
                .accessibilityHidden(true)
            Text(name)
                .font(.body.weight(.bold))
                .foregroundStyle(Farbe.text)
                .multilineTextAlignment(.leading)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 9)
        .padding(.leading, 5 + 11)
        .padding(.trailing, 11)
        .background { RoundedRectangle(cornerRadius: 10).fill(Farbe.flaeche) }
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Farbe.rand, lineWidth: 1) }
        .overlay(alignment: .leading) { Farbe.primaer.frame(width: 5) }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
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
