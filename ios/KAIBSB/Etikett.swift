import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Maße des Geräte-Etiketts. Wie in KAI (Asset Manager → QR-Code drucken): Bandbreite 12, 18, 24 oder 36 mm,
/// Etikettenlänge 20–120 mm (Vorgabe 40). Das Bild liegt so, wie der Brother-Drucker es erwartet:
/// Bildbreite = Bandbreite, Bildhöhe = Etikettenlänge.
struct EtikettMasse: Equatable {
    let bandMm: Double
    let laengeMm: Double
    let qrMm: Double
    let randMm: Double

    /// 10 Bildpunkte je Millimeter — so druckte auch die frühere App; der Drucker rechnet auf seine Auflösung um.
    static let pixelProMm: Double = 10
    /// 12 und 18 mm dazu (Peter 23.11.: im PT-P710BT liegt gerade 12-mm-Band). PT-P710BT und PT-P750W nehmen höchstens 24 mm.
    static let bandbreiten = [12, 18, 24, 36]
    static let laengeBereich = 20...120

    var pixelBreite: Int { Int((bandMm * Self.pixelProMm).rounded()) }
    var pixelHoehe: Int { Int((laengeMm * Self.pixelProMm).rounded()) }

    /// QR-Code fast so breit wie das Band (1 mm Rand) — ein großer Code wird von der Kamera besser erkannt.
    /// Darunter bleiben mindestens 5 mm für den Namen; ist das Etikett dafür zu kurz, wird es so weit verlängert.
    static func berechnen(band: Int, laenge: Int) -> EtikettMasse {
        let band = Double(max(12, band))
        let rand = 1.0
        let qr = band - 2 * rand
        let gewuenscht = Double(min(max(laenge, laengeBereich.lowerBound), laengeBereich.upperBound))
        let laenge = max(gewuenscht, qr + 2 * rand + 5)
        return EtikettMasse(bandMm: band, laengeMm: laenge, qrMm: qr, randMm: rand)
    }
}

/// Zeichnet das Etikett: QR-Code mit dem KAI-Link des Geräts, darunter der Name — wie das Etikett aus KAI.
enum Etikett {
    static func bild(name: String, qrInhalt: String, masse: EtikettMasse) -> UIImage {
        let p = EtikettMasse.pixelProMm
        let breite = CGFloat(masse.pixelBreite)
        let hoehe = CGFloat(masse.pixelHoehe)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let zeichner = UIGraphicsImageRenderer(size: CGSize(width: breite, height: hoehe), format: format)
        return zeichner.image { kontext in
            UIColor.white.setFill()
            kontext.fill(CGRect(x: 0, y: 0, width: breite, height: hoehe))

            let rand = CGFloat(masse.randMm * p)
            let qrSeite = CGFloat(masse.qrMm * p)
            if let qr = qrBild(qrInhalt, seite: qrSeite) {
                kontext.cgContext.interpolationQuality = .none
                qr.draw(in: CGRect(x: rand, y: rand, width: qrSeite, height: qrSeite))
            }

            // Name scharf in Schwarz, so groß wie es die Fläche zulässt.
            let abstand = CGFloat(1 * p)
            let textFlaeche = CGRect(x: rand, y: rand + qrSeite + abstand,
                                     width: breite - 2 * rand, height: hoehe - qrSeite - abstand - 2 * rand)
            let absatz = NSMutableParagraphStyle()
            absatz.alignment = .center
            absatz.lineBreakMode = .byTruncatingTail
            var groesse = max(10, min(textFlaeche.height * 0.8, CGFloat(8 * p)))
            func merkmale(_ g: CGFloat) -> [NSAttributedString.Key: Any] {
                [.font: UIFont.systemFont(ofSize: g, weight: .bold), .foregroundColor: UIColor.black, .paragraphStyle: absatz]
            }
            while groesse > 10, (name as NSString).size(withAttributes: merkmale(groesse)).width > textFlaeche.width {
                groesse -= 1
            }
            let hoeheText = (name as NSString).size(withAttributes: merkmale(groesse)).height
            let zeile = CGRect(x: textFlaeche.minX, y: textFlaeche.minY + max(0, (textFlaeche.height - hoeheText) / 2),
                               width: textFlaeche.width, height: hoeheText)
            (name as NSString).draw(in: zeile, withAttributes: merkmale(groesse))
        }
    }

    static func qrBild(_ inhalt: String, seite: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(inhalt.utf8)
        filter.correctionLevel = "M"
        guard let ausgabe = filter.outputImage else { return nil }
        let faktor = seite / ausgabe.extent.width
        let skaliert = ausgabe.transformed(by: CGAffineTransform(scaleX: faktor, y: faktor))
        guard let cg = CIContext().createCGImage(skaliert, from: skaliert.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
