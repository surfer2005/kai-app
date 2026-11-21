import SwiftUI

struct EinstellungenAnsicht: View {
    @EnvironmentObject private var app: AppZustand
    @AppStorage("drucker") private var druckerWahl = DruckerModell.ptP710BT.rawValue
    @AppStorage("band") private var band = 24
    @AppStorage("laenge") private var laenge = 40
    @AppStorage("druckerIP") private var druckerIP = ""

    @State private var angemeldet: Bool?
    @State private var gekoppelt: [String] = []
    @State private var sucht = false
    @State private var gefunden: [GefundenerDrucker]?
    @State private var wechselZiel: Umgebung?

    private var modell: DruckerModell { DruckerModell(rawValue: druckerWahl) ?? .ptP710BT }

    var body: some View {
        Group {
            Form {
                Section {
                    ForEach(Umgebung.allCases) { u in
                        Button { if u != app.umgebung { wechselZiel = u } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) { Text(u.name); UmgebungsKennzeichen(umgebung: u) }
                                    Text(u.adresse).font(.caption.monospaced()).foregroundStyle(Farbe.textLeise)
                                }
                                Spacer()
                                if u == app.umgebung { Image(systemName: "checkmark").foregroundStyle(Farbe.primaer) }
                            }
                        }
                        .foregroundStyle(Farbe.text)
                    }
                } header: { Text("Verbindung") } footer: {
                    Text("Test und Produktion liegen auf demselben Rechner, haben aber getrennte Anmeldungen — nach einem Wechsel meldest du dich dort neu an.")
                }

                Section("Anmeldung") {
                    HStack {
                        Text("Status")
                        Spacer()
                        switch angemeldet {
                        case .some(true): Text("angemeldet").foregroundStyle(Farbe.gruenText)
                        case .some(false): Text("nicht angemeldet").foregroundStyle(Farbe.textLeise)
                        case .none: ProgressView().controlSize(.small)
                        }
                    }
                    Button("In KAI anmelden") { app.reiter = .assetManager }
                        .disabled(angemeldet == true)
                    Button("Abmelden", role: .destructive) {
                        Task { await app.abmelden(); await pruefen() }
                    }
                    .disabled(angemeldet != true)
                }

                Section {
                    Picker("Drucker", selection: $druckerWahl) {
                        ForEach(DruckerModell.allCases) { m in Text("\(m.name) · \(m.verbindung)").tag(m.rawValue) }
                    }
                    .pickerStyle(.inline)
                    if modell == .ptP710BT {
                        if gekoppelt.isEmpty {
                            Text("Kein PT-P710BT gekoppelt. Drucker einschalten und in den iPhone-Einstellungen unter Bluetooth koppeln.")
                                .font(.footnote).foregroundStyle(Farbe.textLeise)
                        } else {
                            ForEach(gekoppelt, id: \.self) { d in Label(d, systemImage: "checkmark.circle").foregroundStyle(Farbe.gruenText) }
                        }
                        Button("Gekoppelte Drucker neu prüfen") { gekoppelt = DruckDienst.gekoppelteDrucker() }
                    } else {
                        TextField("IP-Adresse des PT-P750W", text: $druckerIP)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button {
                            Task { sucht = true; gefunden = await DruckDienst.wlanSuchen(); sucht = false }
                        } label: {
                            HStack { Text("Im WLAN suchen"); if sucht { Spacer(); ProgressView() } }
                        }
                        .disabled(sucht || !DruckDienst.bausteinVorhanden)
                        if let gefunden {
                            if gefunden.isEmpty {
                                Text("Kein Brother-Drucker im WLAN gefunden.").font(.footnote).foregroundStyle(Farbe.textLeise)
                            }
                            ForEach(gefunden) { d in
                                Button { druckerIP = d.ip } label: {
                                    HStack { Text(d.modell); Spacer(); Text(d.ip).monospaced(); if d.ip == druckerIP { Image(systemName: "checkmark") } }
                                }
                            }
                        }
                    }
                    Picker("Bandbreite", selection: $band) {
                        ForEach(EtikettMasse.bandbreiten, id: \.self) { b in Text("\(b) mm").tag(b) }
                    }
                    .pickerStyle(.segmented)
                    if !modell.passt(band: band) {
                        Text("\(modell.name) nimmt höchstens \(modell.hoechsteBandbreite) mm.").font(.footnote).foregroundStyle(Farbe.rotText)
                    }
                    Stepper(value: $laenge, in: EtikettMasse.laengeBereich, step: 5) {
                        HStack { Text("Etikettenlänge"); Spacer(); Text("\(laenge) mm").monospacedDigit() }
                    }
                } header: { Text("Etikettendrucker") } footer: {
                    Text(DruckDienst.bausteinVorhanden
                         ? "Drucker-Baustein (Brother-SDK) ist eingebunden."
                         : "Drucker-Baustein fehlt — das Brother-SDK wird einmal in den Ordner „Frameworks“ des Xcode-Projekts kopiert (siehe Anleitung). Bis dahin geht nur die Vorschau.")
                }

                Section("Über") {
                    LabeledContent("Version", value: AppInfo.version)
                    LabeledContent("Verbunden mit", value: app.umgebung?.adresse ?? "—")
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                if let u = app.umgebung {
                    ToolbarItem(placement: .topBarTrailing) { UmgebungsKennzeichen(umgebung: u) }
                }
            }
            .confirmationDialog("Umgebung wechseln?", isPresented: Binding(get: { wechselZiel != nil }, set: { if !$0 { wechselZiel = nil } }),
                                titleVisibility: .visible, presenting: wechselZiel) { ziel in
                Button("Mit \(ziel.name) verbinden") { app.verbinden(ziel); wechselZiel = nil; Task { await pruefen() } }
                Button("Abbrechen", role: .cancel) { wechselZiel = nil }
            } message: { ziel in
                Text("Die App lädt danach KAI \(ziel.name) (\(ziel.adresse)).")
            }
        }
        .task {
            gekoppelt = DruckDienst.gekoppelteDrucker()
            await pruefen()
        }
    }

    private func pruefen() async {
        angemeldet = nil
        // Die KAI-Seite braucht nach dem Laden einen Moment, bis das Token gelesen werden kann.
        try? await Task.sleep(nanoseconds: 400_000_000)
        angemeldet = await app.token() != nil
    }
}
