import UIKit
import ExternalAccessory
#if canImport(BRLMPrinterKit)
import BRLMPrinterKit
#endif

/// Die Etikettendrucker. PT-P910BT dazu (Peter 23.11.): steht — anders als der PT-P710BT — auf Brothers Liste der vom SDK
/// unterstützten Drucker, für die Verteilung der App (Brother-Freigabe bei Apple) der sicherere Weg.
enum DruckerModell: String, CaseIterable, Identifiable {
    case ptP710BT = "PT-P710BT"
    case ptP910BT = "PT-P910BT"
    case ptP750W = "PT-P750W"

    var id: String { rawValue }
    var name: String { "Brother \(rawValue)" }
    var istBluetooth: Bool { self != .ptP750W }
    var verbindung: String { istBluetooth ? "Bluetooth" : "WLAN" }
    /// PT-P710BT und PT-P750W nehmen TZe-Bänder bis 24 mm, der PT-P910BT bis 36 mm.
    var hoechsteBandbreite: Int { self == .ptP910BT ? 36 : 24 }
    /// Kurzname, unter dem sich der Drucker per Bluetooth meldet (z. B. „PT-P710BT1234“ enthält „P710BT“).
    var kurz: String { rawValue.replacingOccurrences(of: "PT-", with: "") }
    func passt(band: Int) -> Bool { band <= hoechsteBandbreite }
}

enum DruckFehler: LocalizedError {
    case bausteinFehlt
    case bandZuBreit(Int, DruckerModell)
    case keinBluetoothDrucker
    case festerDruckerAus(String)
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
            "Kein Bluetooth-Drucker verbunden. Drucker einschalten und auf „Drucker suchen“ tippen — iOS zeigt dann die Brother-Drucker in der Nähe."
        case let .festerDruckerAus(name):
            "Der feste Drucker \(name) ist nicht verbunden. Bitte einschalten — das iPhone verbindet ihn dann von selbst. "
                + "Einen anderen Drucker wählst du unter „Mehr → Einstellungen“."
        case .keineAdresse:
            "Für den PT-P750W fehlt die IP-Adresse. Bitte in den Einstellungen eintragen oder im WLAN suchen."
        case let .verbindung(text):
            "Keine Verbindung zum Drucker: \(text)"
        case let .druck(text):
            "Druck fehlgeschlagen: \(text)"
        }
    }
}

/// Ein über Bluetooth verbundener Brother-Drucker (PT-P710BT). Die Seriennummer unterscheidet mehrere gleiche Drucker.
struct BluetoothDrucker: Identifiable, Equatable, Sendable {
    let name: String
    let serie: String
    var id: String { serie }
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

    /// Verbundene Brother-Drucker (Bluetooth), alle — bei zwei eingeschalteten Druckern stehen beide hier.
    /// Geht auch ohne SDK — iOS kennt das Zubehör selbst.
    static func gekoppelteDrucker() -> [BluetoothDrucker] {
        EAAccessoryManager.shared().connectedAccessories
            .filter(istBrotherPT)
            .map { BluetoothDrucker(name: $0.name, serie: $0.serialNumber) }
    }

    /// Brother-Drucker in der Nähe suchen und koppeln — mit der Auswahl von iOS, aus der App heraus
    /// (Peter 23.11.: „Bluetooth auswählen klappt nicht“ — über die iPhone-Einstellungen ließ sich der Drucker nicht koppeln;
    /// so machen es auch Brothers eigene Apps). Rückgabe: Fehlertext oder nil, wenn ein Drucker verbunden ist.
    @MainActor static func druckerSuchen() async -> String? {
        await withCheckedContinuation { (fortsetzung: CheckedContinuation<String?, Never>) in
            EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: nil) { fehler in
                guard let fehler else { fortsetzung.resume(returning: nil); return }
                let code = (fehler as NSError).code
                switch EABluetoothAccessoryPickerError.Code(rawValue: code) {
                case .alreadyConnected: fortsetzung.resume(returning: nil)
                case .resultNotFound: fortsetzung.resume(returning: "Kein Brother-Drucker in der Nähe gefunden. Ist er eingeschaltet und die Bluetooth-Lampe an?")
                case .resultCancelled: fortsetzung.resume(returning: "Suche abgebrochen.")
                default: fortsetzung.resume(returning: "Koppeln fehlgeschlagen: \(fehler.localizedDescription)")
                }
            }
        }
    }

    /// Der PT-P710BT steht nicht in Brothers Modellliste, deshalb findet die Bluetooth-Suche des SDK ihn nicht.
    /// Stattdessen: das von iOS gekoppelte Zubehör direkt nehmen (Weg aus Peters Test-Projekt „MyTestApp“).
    private static func istBrotherPT(_ zubehoer: EAAccessory) -> Bool {
        zubehoer.name.contains("P710BT") || zubehoer.name.contains("P910BT") || zubehoer.protocolStrings.contains("com.brother.ptcbp")
            || zubehoer.protocolStrings.contains("com.brother.ptcbep")
    }

    /// Druckt das Etikett. Rückgabe beim PT-P710BT: Name und Seriennummer des Druckers, auf dem gedruckt wurde
    /// (die App merkt ihn sich danach als festen Drucker, Peter 23.11.).
    @discardableResult
    static func drucken(_ bild: UIImage, modell: DruckerModell, band: Int, ip: String, serie: String = "",
                        festerName: String = "") async throws -> BluetoothDrucker? {
        guard modell.passt(band: band) else { throw DruckFehler.bandZuBreit(band, modell) }
        #if canImport(BRLMPrinterKit)
        guard let cg = bild.cgImage else { throw DruckFehler.druck("Etikett-Bild ist leer.") }
        let adresse = ip.trimmingCharacters(in: .whitespaces)
        if modell == .ptP750W, adresse.isEmpty { throw DruckFehler.keineAdresse }
        // Suche, Verbindung und Druck blockieren — nicht auf dem Hauptthread.
        return try await Task.detached(priority: .userInitiated) { () throws -> BluetoothDrucker? in
            let kanal: BRLMChannel
            var benutzt: BluetoothDrucker?
            switch modell {
            case .ptP710BT, .ptP910BT:
                // Fester Drucker (Seriennummer aus den Einstellungen) — nur der; ohne festen Drucker der erste verbundene
                let verbunden = EAAccessoryManager.shared().connectedAccessories.filter(DruckDienst.istBrotherPT)
                let zubehoer: EAAccessory
                if !serie.isEmpty {
                    guard let z = verbunden.first(where: { $0.serialNumber == serie }) else {
                        throw DruckFehler.festerDruckerAus(festerName.isEmpty ? "\(modell.rawValue) (\(serie))" : festerName)
                    }
                    zubehoer = z
                } else {
                    // ohne festen Drucker: zuerst einer des gewählten Modells, sonst der erste Brother-Drucker
                    guard let z = verbunden.first(where: { $0.name.contains(modell.kurz) }) ?? verbunden.first else {
                        throw DruckFehler.keinBluetoothDrucker
                    }
                    zubehoer = z
                }
                benutzt = BluetoothDrucker(name: zubehoer.name, serie: zubehoer.serialNumber)
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
            return benutzt
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
            if rest > 0 { try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000)) }
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
        case .ptP910BT: .PT_P910BT
        case .ptP750W: .PT_P750W
        }
    }
}
#endif
