import SwiftUI
import AVFoundation
import Vision

/// Kamera mit Code-Erkennung über Apples Vision (wie in Peters früherer App): jedes Bild wird ganz ausgewertet,
/// das ist bei kleinen Etiketten deutlich zuverlässiger als der ältere Metadaten-Leser. Der grüne Rahmen ist nur
/// eine Hilfe zum Ausrichten, er schränkt die Erkennung nicht ein.
struct KameraAnsicht: UIViewControllerRepresentable {
    var aktiv: Bool
    let gefunden: (String) -> Void

    func makeUIViewController(context: Context) -> KameraController {
        let k = KameraController()
        k.gefunden = gefunden
        return k
    }

    func updateUIViewController(_ k: KameraController, context: Context) {
        k.gefunden = gefunden
        k.setzeAktiv(aktiv)
    }

    static var verfuegbar: Bool { KameraController.geraet() != nil }
}

final class KameraController: UIViewController {
    var gefunden: ((String) -> Void)? {
        get { leser.gefunden }
        set { leser.gefunden = newValue }
    }
    private let sitzung = AVCaptureSession()
    private let ausgabe = AVCaptureVideoDataOutput()
    private let warteschlange = DispatchQueue(label: "kai.scan.kamera", qos: .userInitiated)
    private let leser = CodeLeser()
    private let rahmen = CAShapeLayer()
    private var vorschau: AVCaptureVideoPreviewLayer?
    private var eingerichtet = false
    private var sollAktiv = false

    /// Die mehrteilige Rückkamera schaltet aus der Nähe selbst auf das Weitwinkel-Objektiv (Makro) um —
    /// so werden auch kleine 24-mm-Etiketten scharf.
    nonisolated static func geraet() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
                                         mediaType: .video, position: .back).devices.first
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        rahmen.strokeColor = UIColor.systemGreen.cgColor
        rahmen.fillColor = UIColor.clear.cgColor
        rahmen.lineWidth = 3
    }

    func setzeAktiv(_ aktiv: Bool) {
        sollAktiv = aktiv
        if aktiv { einrichtenWennNoetig() }
        let s = sitzung
        warteschlange.async {
            if aktiv, !s.isRunning { s.startRunning() }
            if !aktiv, s.isRunning { s.stopRunning() }
        }
    }

    private func einrichtenWennNoetig() {
        guard !eingerichtet, let geraet = Self.geraet(), let eingang = try? AVCaptureDeviceInput(device: geraet) else { return }
        eingerichtet = true
        if (try? geraet.lockForConfiguration()) != nil {
            if geraet.isFocusModeSupported(.continuousAutoFocus) { geraet.focusMode = .continuousAutoFocus }
            if geraet.isAutoFocusRangeRestrictionSupported { geraet.autoFocusRangeRestriction = .near }
            geraet.unlockForConfiguration()
        }
        sitzung.beginConfiguration()
        if sitzung.canSetSessionPreset(.hd1920x1080) { sitzung.sessionPreset = .hd1920x1080 }
        if sitzung.canAddInput(eingang) { sitzung.addInput(eingang) }
        if sitzung.canAddOutput(ausgabe) {
            ausgabe.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            ausgabe.alwaysDiscardsLateVideoFrames = true
            ausgabe.setSampleBufferDelegate(leser, queue: warteschlange)
            sitzung.addOutput(ausgabe)
        }
        sitzung.commitConfiguration()
        let schicht = AVCaptureVideoPreviewLayer(session: sitzung)
        schicht.videoGravity = .resizeAspectFill
        schicht.frame = view.bounds
        view.layer.addSublayer(schicht)
        view.layer.addSublayer(rahmen)
        vorschau = schicht
        rahmenZeichnen()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        vorschau?.frame = view.bounds
        rahmenZeichnen()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setzeAktiv(false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if sollAktiv { setzeAktiv(true) }
    }

    private func rahmenZeichnen() {
        guard view.bounds.width > 0 else { return }
        let seite = min(view.bounds.width, view.bounds.height) * 0.65
        let r = CGRect(x: (view.bounds.width - seite) / 2, y: (view.bounds.height - seite) / 2, width: seite, height: seite)
        rahmen.path = UIBezierPath(roundedRect: r, cornerRadius: 16).cgPath
    }
}

/// Wertet die Kamerabilder aus (läuft auf der Kamera-Warteschlange, nicht auf dem Hauptthread).
final class CodeLeser: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var gefunden: ((String) -> Void)?
    private var wertetAus = false   // nur ein Bild zur Zeit auswerten
    private var zuletzt: (text: String, zeit: Date)?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !wertetAus, let bild = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        wertetAus = true
        defer { wertetAus = false }
        let anfrage = VNDetectBarcodesRequest()
        anfrage.symbologies = [.qr, .dataMatrix, .aztec, .code128, .code39, .code93, .ean13, .ean8, .itf14, .pdf417]
        // Rohbild nicht vorher drehen — Vision bekommt die Lage (Hochformat, Rückkamera) einmal mitgeteilt.
        let auswertung = VNImageRequestHandler(cvPixelBuffer: bild, orientation: .right, options: [:])
        guard (try? auswertung.perform([anfrage])) != nil,
              let text = anfrage.results?.compactMap(\.payloadStringValue).first(where: { !$0.isEmpty }) else { return }
        melden(text)
    }

    /// Derselbe Code innerhalb von 3 Sekunden zählt nur einmal (sonst feuert ein Etikett bei jedem Bild).
    private func melden(_ text: String) {
        let jetzt = Date()
        if let z = zuletzt, z.text == text, jetzt.timeIntervalSince(z.zeit) < 3 { return }
        zuletzt = (text, jetzt)
        let rueckmeldung = gefunden
        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            rueckmeldung?(text)
        }
    }
}
