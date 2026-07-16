enum LyricRenderWindow {
    static func indices(lineCount: Int, currentIndex: Int) -> [Int] {
        guard lineCount > 0 else { return [] }
        guard currentIndex >= 0 else { return [0] }

        let current = min(currentIndex, lineCount - 1)
        let lowerBound = max(0, current - 1)
        let upperBound = min(lineCount - 1, current + 1)
        return Array(lowerBound...upperBound)
    }
}
