import AppKit

enum OverlayStyle {
    static let windowWidth: CGFloat = 1_000
    static let windowHeight: CGFloat = 200
    static let currentLineFromBottom: CGFloat = 90
    static let defaultFontSize: CGFloat = 30
    static let horizontalPadding: CGFloat = 34
    static let hitMargin: CGFloat = 16

    static func rowHeight(fontSize: CGFloat) -> CGFloat {
        max(54, fontSize + 24)
    }

    static func neighborFontSize(fontSize: CGFloat) -> CGFloat {
        fontSize * (19 / defaultFontSize)
    }

    static func currentLineFont(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .bold)
    }
}
