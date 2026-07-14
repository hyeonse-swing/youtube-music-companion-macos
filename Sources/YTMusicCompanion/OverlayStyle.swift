import AppKit

enum OverlayStyle {
    static let windowWidth: CGFloat = 1_000
    static let windowHeight: CGFloat = 180
    static let rowHeight: CGFloat = 54
    static let currentLineFromBottom: CGFloat = 78
    static let currentFontSize: CGFloat = 30
    static let neighborFontSize: CGFloat = 19
    static let horizontalPadding: CGFloat = 34
    static let hitMargin: CGFloat = 16

    static var currentLineFont: NSFont {
        .systemFont(ofSize: currentFontSize, weight: .bold)
    }
}
