import SwiftUI

/// „Mehr → Leiste anpassen“ (Peter 2026-11-23): welche drei Bereiche unten zwischen „Start“ und „Mehr“ stehen und in welcher
/// Reihenfolge. Angeboten wird nur, was KAI nach den Rechten erlaubt; „Start“ und „Mehr“ sind fest. Gemerkt auf diesem iPhone.
struct LeisteAnpassenAnsicht: View {
    @EnvironmentObject private var app: AppZustand

    private var leiste: Leiste { app.leiste }

    var body: some View {
        List {
            Section {
                festeZeile("Start", symbol: "house", hinweis: "immer ganz links")
                ForEach(Array(leiste.unten.enumerated()), id: \.element) { i, b in
                    HStack(spacing: 12) {
                        Image(systemName: b.symbol).foregroundStyle(Farbe.primaer).frame(width: 26)
                        Text(b.name)
                        Spacer()
                        Button { setzen(Leiste.verschieben(b, um: -1, in: leiste.unten)) } label: { Image(systemName: "arrow.up") }
                            .disabled(i == 0)
                            .accessibilityLabel("\(b.name) nach links")
                        Button { setzen(Leiste.verschieben(b, um: 1, in: leiste.unten)) } label: { Image(systemName: "arrow.down") }
                            .disabled(i == leiste.unten.count - 1)
                            .accessibilityLabel("\(b.name) nach rechts")
                        Button { setzen(Leiste.entfernen(b, aus: leiste.unten)) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(Farbe.rotText)
                        }
                        .accessibilityLabel("\(b.name) unter „Mehr“ stellen")
                    }
                    .buttonStyle(.borderless)
                }
                festeZeile("Mehr", symbol: "ellipsis.circle", hinweis: "immer ganz rechts")
            } header: {
                Text("Unten in der Leiste (\(leiste.unten.count) von \(Leiste.hoechstens))")
            } footer: {
                Text("Die Reihenfolge von oben nach unten ist die Reihenfolge in der Leiste von links nach rechts.")
            }

            Section {
                if leiste.mehr.isEmpty {
                    Text("Alle deine Bereiche stehen unten.").foregroundStyle(Farbe.textLeise)
                }
                ForEach(leiste.mehr) { b in
                    HStack(spacing: 12) {
                        Image(systemName: b.symbol).foregroundStyle(Farbe.primaer).frame(width: 26)
                        Text(b.name)
                        Spacer()
                        Button { setzen(Leiste.hinzufuegen(b, zu: leiste.unten)) } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Farbe.primaer)
                        }
                        .disabled(leiste.unten.count >= Leiste.hoechstens)
                        .accessibilityLabel("\(b.name) nach unten in die Leiste")
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Unter „Mehr“")
            } footer: {
                Text(leiste.unten.count >= Leiste.hoechstens
                     ? "Unten sind drei Plätze frei wählbar. Nimm erst einen Bereich heraus, um einen anderen hineinzustellen."
                     : "Mit + kommt ein Bereich nach unten in die Leiste.")
            }

            Section {
                Button("Vorgabe wiederherstellen") { app.leisteSetzen(nil) }
                    .disabled(app.leistenWahl == nil)
            } footer: {
                Text("Welche Bereiche es für dich gibt, legt KAI über deine Rechte fest. Vorgabe: die ersten drei in der Reihenfolge Dienstanweisung, Meldungen, Störmeldedienst bzw. Asset Manager, Scannen, Informationen, Schiffstatus, KI-Chat — wer den Störmeldedienst lesen darf, hat ihn statt des Asset Managers unten.")
            }
        }
        .navigationTitle("Leiste anpassen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func festeZeile(_ name: String, symbol: String, hinweis: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Farbe.textLeise).frame(width: 26)
            Text(name).foregroundStyle(Farbe.textLeise)
            Spacer()
            Text(hinweis).font(.footnote).foregroundStyle(Farbe.textLeise)
            Image(systemName: "lock.fill").font(.footnote).foregroundStyle(Farbe.textLeise)
        }
    }

    private func setzen(_ neu: [Bereich]) { app.leisteSetzen(neu) }
}
