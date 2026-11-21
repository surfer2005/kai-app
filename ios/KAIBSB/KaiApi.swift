import Foundation

struct KaiFehler: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

/// Ein Gerät aus dem Asset Manager — nur die Felder, die die App braucht (Liste und Detail liefern mehr).
struct GeraetKurz: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String?
    let inventoryNumber: String?
    let serialNumber: String?
    let location: String?
    let deviceType: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id, name, location, status
        case inventoryNumber = "inventory_number"
        case serialNumber = "serial_number"
        case deviceType = "device_type"
    }

    var anzeigename: String { (name?.isEmpty == false ? name : nil) ?? "Gerät \(id)" }

    var zusatz: String {
        [deviceType, location, serialNumber.map { "SN \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct ListenAntwort: Decodable {
    let items: [GeraetKurz]
}

private struct FehlerAntwort: Decodable {
    let error: String?
}

/// Spricht direkt mit der KAI-API — mit dem Token, mit dem du dich in der KAI-Seite angemeldet hast.
struct KaiApi {
    let umgebung: Umgebung
    let token: String?
    var sitzung: URLSession = .shared

    /// `GET /api/asset-manager/assets/:id`
    func geraet(_ id: Int) async throws -> GeraetKurz {
        try await holen("asset-manager/assets/\(id)", als: GeraetKurz.self)
    }

    /// `GET /api/asset-manager/assets?q=…` — dieselbe Suche wie im Asset Manager (Name, Inventarnummer …).
    func geraeteSuchen(_ begriff: String) async throws -> [GeraetKurz] {
        let q = begriff.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? begriff
        return try await holen("asset-manager/assets?q=\(q)&limit=20", als: ListenAntwort.self).items
    }

    /// Alte Asset-Manager-Nummer → KAI-Gerät. KAI kennt die Übersetzung (`/api/go/asset/:alteNr` leitet nach
    /// `#am_assets?asset=<id>` um). Die App folgt der Umleitung nicht, sondern liest nur die Nummer daraus —
    /// die Umleitung zeigt in der Testumgebung sonst auf die Produktion.
    func altesGeraetAufloesen(_ altId: Int) async throws -> Int? {
        var anfrage = URLRequest(url: umgebung.api("go/asset/\(altId)"))
        anfrage.timeoutInterval = 15
        let (_, antwort) = try await sitzung.data(for: anfrage, delegate: KeineUmleitung())
        guard let http = antwort as? HTTPURLResponse else { throw KaiFehler(text: "Keine Antwort von KAI.") }
        guard (300..<400).contains(http.statusCode), let ort = http.value(forHTTPHeaderField: "Location") else {
            throw KaiFehler(text: "KAI antwortet mit \(http.statusCode).")
        }
        return Self.idAusUmleitung(ort)
    }

    /// Geräte-Nummer aus dem Umleitungsziel, z. B. 2760 aus „/#am_assets?asset=2760“. Ohne Nummer → nil
    /// (KAI kennt die alte Nummer nicht und springt nur in die Liste).
    static func idAusUmleitung(_ ort: String) -> Int? {
        guard let raute = ort.firstIndex(of: "#") else { return nil }
        let fragment = String(ort[ort.index(after: raute)...])
        guard fragment.hasPrefix("am_assets") else { return nil }
        return ScanAuswertung.zahl(nach: "asset=", in: fragment)
    }

    // MARK: - Hilfen

    private func holen<T: Decodable>(_ pfad: String, als: T.Type) async throws -> T {
        guard let token, !token.isEmpty else {
            throw KaiFehler(text: "Du bist in KAI nicht angemeldet. Bitte zuerst im Reiter „Asset Manager“ anmelden.")
        }
        guard let url = URL(string: umgebung.adresse + "/api/" + pfad) else { throw KaiFehler(text: "Ungültige Adresse.") }
        var anfrage = URLRequest(url: url)
        anfrage.timeoutInterval = 20
        anfrage.cachePolicy = .reloadIgnoringLocalCacheData
        anfrage.setValue("application/json", forHTTPHeaderField: "Accept")
        anfrage.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (daten, antwort) = try await sitzung.data(for: anfrage)
        guard let http = antwort as? HTTPURLResponse else { throw KaiFehler(text: "Keine Antwort von KAI.") }
        if http.statusCode == 401 {
            throw KaiFehler(text: "Die Anmeldung ist abgelaufen. Bitte im Reiter „Asset Manager“ neu anmelden.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = (try? JSONDecoder().decode(FehlerAntwort.self, from: daten))?.error
            throw KaiFehler(text: text ?? "KAI antwortet mit Fehler \(http.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: daten)
    }
}

/// Folgt keiner Umleitung — die Antwort mit `Location` kommt so bei uns an.
final class KeineUmleitung: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
