enum LyricRenderWindow {
    static func indices(lineCount: Int, currentIndex: Int) -> Range<Int> {
        guard lineCount > 0 else { return 0..<0 }
        guard currentIndex >= 0 else { return 0..<1 }

        let current = min(currentIndex, lineCount - 1)
        let lowerBound = max(0, current - 1)
        let upperBound = current < lineCount - 1 ? current + 2 : lineCount
        return lowerBound..<upperBound
    }
}
