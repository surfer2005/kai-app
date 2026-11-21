import UIKit
import ExternalAccessory
#if canImport(BRLMPrinterKit)
import BRLMPrinterKit
#endif

/// Die beiden Etikettendrucker im Einsatz.
enum DruckerModell: String, CaseIterable, Identifiable {
    case ptP710BT = "PT-P710BT"
    case ptP750W = "PT-P750W"

    var id: String { rawValue }
    var name: String { "Brother \(rawValue)" }
    var verbindung: String { self == .ptP710BT ? "Bluetooth" : "WLAN" }
    /// Beide nehmen TZe-Bänder bis 24 mm.
    var hoechsteBandbreite: Int { 24 }
    func passt(band: Int) -> Bool { band <= hoechsteBandbreite }
}

enum DruckFehler: LocalizedError {
    case bausteinFehlt
    case bandZuBreit(Int, DruckerModell)
    case keinBluetoothDrucker
    case keineAdresse
    case verbindung(String)
    case druck(String)

    var errorDescription: String? {
        switch self {
        case .bausteinFehlt:
            "Drucker-Baustein fehlt: Das Brother-SDK (BRLMPrinterKit) ist in dieser Fassung nicht eingebunden. "
                + "Die Vorschau geht, gedruckt werden kann erst mit dem Baustein (siehe Anleitung, Ordner „Frameworks“)."
        case let .bandZuBreit(band, modell):
            "\(modell.name) nimmt höchstens \(modell.hoechsteBandbreite) mm breites Band — eingestellt sind \(band) mm."
        case .keinBluetoothDrucker:
            "Kein PT-P710BT gefunden. Drucker einschalten und einmal in den iPhone-Einstellungen unter Bluetooth koppeln."
        case .keineAdresse:
            "Für den PT-P750W fehlt die IP-Adresse. Bitte in den Einstellungen eintragen oder im WLAN suchen."
        case let .verbindung(text):
            "Keine Verbindung zum Drucker: \(text)"
        case let .druck(text):
            "Druck fehlgeschlagen: \(text)"
        }
    }
}

/// Ein im WLAN gefundener Brother-Drucker.
struct GefundenerDrucker: Identifiable, Equatable {
    let ip: String
    let modell: String
    var id: String { ip }
}

/// Druck auf Brother-Etikettendrucker über das Brother Print SDK v4.
/// Das SDK liegt NICHT im öffentlichen Repository (Lizenz von Brother): ohne es baut die App trotzdem,
/// `bausteinVorhanden` ist dann `false` und Drucken meldet „Drucker-Baustein fehlt“.
enum DruckDienst {
    static var bausteinVorhanden: Bool {
        #if canImport(BRLMPrinterKit)
        true
        #else
        false
        #endif
    }

    /// Mit dem iPhone gekoppelte Brother-Drucker (Bluetooth). Geht auch ohne SDK — iOS kennt das Zubehör selbst.
    static func gekoppelteDrucker() -> [String] {
        EAAccessoryManager.shared().connectedAccessories
            .filter(istBrotherPT)
            .map { "\($0.name) (\($0.serialNumber))" }
    }

    /// Der PT-P710BT steht nicht in Brothers Modellliste, deshalb findet die Bluetooth-Suche des SDK ihn nicht.
    /// Stattdessen: das von iOS gekoppelte Zubehör direkt nehmen (Weg aus Peters Test-Projekt „MyTestApp“).
    private static func istBrotherPT(_ zubehoer: EAAccessory) -> Bool {
        zubehoer.name.contains("P710BT") || zubehoer.protocolStrings.contains("com.brother.ptcbp")
    }

    static func drucken(_ bild: UIImage, modell: DruckerModell, band: Int, ip: String) async throws {
        guard modell.passt(band: band) else { throw DruckFehler.bandZuBreit(band, modell) }
        #if canImport(BRLMPrinterKit)
        guard let cg = bild.cgImage else { throw DruckFehler.druck("Etikett-Bild ist leer.") }
        let adresse = ip.trimmingCharacters(in: .whitespaces)
        if modell == .ptP750W, adresse.isEmpty { throw DruckFehler.keineAdresse }
        // Suche, Verbindung und Druck blockieren — nicht auf dem Hauptthread.
        try await Task.detached(priority: .userInitiated) {
            let kanal: BRLMChannel
            switch modell {
            case .ptP710BT:
                guard let zubehoer = EAAccessoryManager.shared().connectedAccessories.first(where: DruckDienst.istBrotherPT) else {
                    throw DruckFehler.keinBluetoothDrucker
                }
                kanal = BRLMChannel(bluetoothSerialNumber: zubehoer.serialNumber)
            case .ptP750W:
                kanal = BRLMChannel(wifiIPAddress: adresse)
            }
            let erzeugt = BRLMPrinterDriverGenerator.open(kanal)
            guard erzeugt.error.code == .noError, let treiber = erzeugt.driver else {
                throw DruckFehler.verbindung(DruckDienst.verbindungsText(erzeugt.error.code))
            }
            defer { treiber.closeChannel() }
            guard let einstellungen = BRLMPTPrintSettings(defaultPrintSettingsWith: modell.brlmModell) else {
                throw DruckFehler.druck("Druckeinstellungen konnten nicht erzeugt werden.")
            }
            einstellungen.labelSize = DruckDienst.labelSize(band)
            einstellungen.autoCut = true
            let fehler = treiber.printImage(with: cg, settings: einstellungen)
            guard fehler.code == .noError else { throw DruckFehler.druck(DruckDienst.druckText(fehler)) }
        }.value
        #else
        throw DruckFehler.bausteinFehlt
        #endif
    }

    /// Brother-Drucker im WLAN suchen (dauert einige Sekunden). Ohne SDK: leere Liste.
    static func wlanSuchen(sekunden: Double = 6) async -> [GefundenerDrucker] {
        #if canImport(BRLMPrinterKit)
        return await Task.detached(priority: .userInitiated) { () -> [GefundenerDrucker] in
            let sammler = DruckDienst.Sammler()
            let option = BRLMNetworkSearchOption()
            option.searchDuration = sekunden
            let beginn = Date()
            let ergebnis = BRLMPrinterSearcher.startNetworkSearch(option) { kanal in
                sammler.dazu(kanal)
            }
            for kanal in ergebnis.channels { sammler.dazu(kanal) }
            let rest = sekunden - Date().timeIntervalSince(beginn)
            if rest > 0 { Thread.sleep(forTimeInterval: rest) }
            return sammler.liste()
        }.value
        #else
        return []
        #endif
    }

    #if canImport(BRLMPrinterKit)
    private static func labelSize(_ band: Int) -> BRLMPTPrintSettingsLabelSize {
        switch band {
        case 12: .width12mm
        case 18: .width18mm
        case 36: .width36mm
        default: .width24mm
        }
    }

    private static func verbindungsText(_ code: BRLMOpenChannelErrorCode) -> String {
        switch code {
        case .timeout: "Zeitüberschreitung — ist der Drucker eingeschaltet und in Reichweite?"
        case .openStreamFailure: "Verbindung konnte nicht geöffnet werden (Drucker belegt oder nicht gekoppelt?)."
        default: "Fehler \(code.rawValue)"
        }
    }

    private static func druckText(_ fehler: BRLMPrintError) -> String {
        switch fehler.code {
        case .printerStatusErrorPaperEmpty: "Kein Band eingelegt."
        case .printerStatusErrorCoverOpen: "Der Deckel ist offen."
        case .printerStatusErrorBusy: "Der Drucker ist beschäftigt."
        case .printerStatusErrorPrinterTurnedOff: "Der Drucker ist ausgeschaltet."
        case .printerStatusErrorBatteryWeak: "Der Akku des Druckers ist schwach."
        case .setLabelSizeError: "Die eingestellte Bandbreite passt nicht zum eingelegten Band."
        case .channelTimeout: "Zeitüberschreitung bei der Verbindung."
        default: "\(fehler.errorDescription) (Fehler \(fehler.code.rawValue))"
        }
    }

    /// Sammelt gefundene Drucker aus dem Rückruf der Suche (kommt auf einem fremden Thread).
    private final class Sammler: @unchecked Sendable {
        private var drucker: [String: GefundenerDrucker] = [:]
        private let sperre = NSLock()

        func dazu(_ kanal: BRLMChannel) {
            let modell = (kanal.extraInfo?.object(forKey: BRLMChannelExtraInfoKeyModelName) as? String) ?? "Brother-Drucker"
            sperre.lock(); defer { sperre.unlock() }
            drucker[kanal.channelInfo] = GefundenerDrucker(ip: kanal.channelInfo, modell: modell)
        }

        func liste() -> [GefundenerDrucker] {
            sperre.lock(); defer { sperre.unlock() }
            return drucker.values.sorted { $0.ip < $1.ip }
        }
    }
    #endif
}

#if canImport(BRLMPrinterKit)
extension DruckerModell {
    var brlmModell: BRLMPrinterModel {
        switch self {
        case .ptP710BT: .PT_P710BT
        case .ptP750W: .PT_P750W
        }
    }
}
#endif
