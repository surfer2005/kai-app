import SwiftUI
import UIKit

/// Farben aus KAI (`client/src/styles/grundwerte.css`), hell und dunkel.
enum Farbe {
    static let primaer = Color(hell: 0x1F6E5C, dunkel: 0x54BC9F)
    static let hintergrund = Color(hell: 0xF3F1EA, dunkel: 0x101613)
    static let flaeche = Color(hell: 0xFFFFFF, dunkel: 0x161D1A)
    static let flaeche2 = Color(hell: 0xEFECE3, dunkel: 0x212B26)
    static let rand = Color(hell: 0xDCD7C8, dunkel: 0x2B342E)
    static let text = Color(hell: 0x17211F, dunkel: 0xECE8DC)
    static let textLeise = Color(hell: 0x57625A, dunkel: 0xAFB7AC)
    static let gelbGrund = Color(hell: 0xF1E6D2, dunkel: 0x3A2E17)
    static let gelbText = Color(hell: 0x7A5512, dunkel: 0xD6A03F)
    static let rotGrund = Color(hell: 0xF3DED7, dunkel: 0x3A211B)
    static let rotText = Color(hell: 0xA8402A, dunkel: 0xE27B62)
    static let gruenGrund = Color(hell: 0xE1EEE0, dunkel: 0x20341F)
    static let gruenText = Color(hell: 0x3F7A45, dunkel: 0x6FBB76)
}

extension Color {
    /// Eine Farbe, die sich mit Hell/Dunkel des iPhones ändert.
    init(hell: UInt32, dunkel: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dunkel) : UIColor(hex: hell) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Kennzeichen der Umgebung („TEST“), gelb wie der Umgebungs-Chip in KAI.
struct UmgebungsKennzeichen: View {
    let umgebung: Umgebung

    var body: some View {
        if let text = umgebung.kennzeichen {
            Text(text)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Farbe.gelbGrund, in: Capsule())
                .foregroundStyle(Farbe.gelbText)
                .accessibilityLabel("Umgebung \(umgebung.name)")
        }
    }
}

/// Hinweiskasten in den Tönen von KAI.
struct Hinweis: View {
    enum Ton { case gelb, rot, gruen }
    let ton: Ton
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .padding(12)
        .foregroundStyle(vorne)
        .background(hinten, in: RoundedRectangle(cornerRadius: 6))
    }

    private var vorne: Color { ton == .gelb ? Farbe.gelbText : ton == .rot ? Farbe.rotText : Farbe.gruenText }
    private var hinten: Color { ton == .gelb ? Farbe.gelbGrund : ton == .rot ? Farbe.rotGrund : Farbe.gruenGrund }
}
