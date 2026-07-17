import AppKit

enum OverlayStyle {
    static let windowWidth: CGFloat = 1_000
    static let windowHeight: CGFloat = 300
    static let currentLineFromBottom: CGFloat = 125
    static let defaultFontSize: CGFloat = 30
    static let horizontalPadding: CGFloat = 34
    static let hitMargin: CGFloat = 16

    static func rowHeight(fontSize: CGFloat, layerCount: Int = 1) -> CGFloat {
        let baseHeight = max(54, fontSize + 24)
        let auxiliaryHeight = romanizedFontSize(fontSize)
            + layerSpacing(fontSize)
        return baseHeight + CGFloat(max(0, layerCount - 1)) * auxiliaryHeight
    }

    static func romanizedFontSize(_ fontSize: CGFloat) -> CGFloat {
        max(13, fontSize * 0.62)
    }

    static func translatedFontSize(_ fontSize: CGFloat) -> CGFloat {
        max(12, fontSize * 0.58)
    }

    static func layerSpacing(_ fontSize: CGFloat) -> CGFloat {
        max(2, fontSize * 0.1)
    }

    static func currentLineFont(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .bold)
    }

    static func romanizedLineFont(size: CGFloat) -> NSFont {
        .systemFont(ofSize: romanizedFontSize(size), weight: .medium)
    }

    static func translatedLineFont(size: CGFloat) -> NSFont {
        .systemFont(ofSize: translatedFontSize(size), weight: .regular)
    }
}
