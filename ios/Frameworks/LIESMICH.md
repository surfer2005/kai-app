# Brother-Baustein (Brother Print SDK v4)

Hierher gehört **`BRLMPrinterKit.xcframework`** — der Druckbaustein von Brother. Er liegt aus Lizenzgründen **nicht**
im öffentlichen Repository.

Einmal hineinkopieren, z. B. aus dem früheren Projekt `Xcode/AssetManager/BRLMPrinterKit.xcframework`
(oder `Xcode/MyTestApp/MyTestApp/BRLMPrinterKit.xcframework`), sodass hier liegt:

    Frameworks/BRLMPrinterKit.xcframework/ios-arm64/BRLMPrinterKit.framework
    Frameworks/BRLMPrinterKit.xcframework/ios-arm64_x86_64-simulator/BRLMPrinterKit.framework

Danach in Xcode einfach ▶ — die App findet den Baustein selbst und bettet ihn signiert ein. Ohne ihn läuft die App
genauso, nur „Drucken“ meldet „Drucker-Baustein fehlt“.
