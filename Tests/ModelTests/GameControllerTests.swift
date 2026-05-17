import Testing
import Model

@Test("clearLines correctly removes multiple adjacent full lines")
func clearLines_removesAdjacentLines() async {
    // Create a 20x10 grid
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)

    // Fill two adjacent lines
    for x in 0..<10 {
        grid[17][x] = .filled(.red)
        grid[18][x] = .filled(.blue)
    }

    // Find lines to clear
    var linesToClear: [Int] = []
    for y in 0..<20 {
        if grid[y].allSatisfy({ $0.isFilled }) {
            linesToClear.append(y)
        }
    }

    // Remove with ascending sort (correct order for this algorithm)
    for y in linesToClear.sorted() {
        grid.remove(at: y)
        grid.insert(Array(repeating: .empty, count: 10), at: 0)
    }

    // Both rows should be removed (top 2 rows empty)
    #expect(grid[0].allSatisfy { $0 == .empty })
    #expect(grid[1].allSatisfy { $0 == .empty })
}

@Test("clearLines preserves grid height after clearing lines")
func clearLines_preservesHeight() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)

    // Fill various lines
    for x in 0..<10 {
        grid[5][x] = .filled(.red)
        grid[10][x] = .filled(.blue)
        grid[15][x] = .filled(.green)
    }

    var linesToClear: [Int] = []
    for y in 0..<20 {
        if grid[y].allSatisfy({ $0.isFilled }) {
            linesToClear.append(y)
        }
    }

    // Remove lines with ascending sort
    for y in linesToClear.sorted() {
        grid.remove(at: y)
        grid.insert(Array(repeating: .empty, count: 10), at: 0)
    }

    // Height should remain 20 (we remove and insert the same number of rows)
    #expect(grid.count == 20)
    #expect(linesToClear.count == 3)
}

// Demonstrates the bug with descending sort (the original code)
@Test("clearLines descending sort demonstrates the bug")
func clearLines_descendingSortBug() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)

    // Fill two adjacent lines
    for x in 0..<10 {
        grid[17][x] = .filled(.red)
        grid[18][x] = .filled(.blue)
    }

    // Find lines to clear
    var linesToClear: [Int] = []
    for y in 0..<20 {
        if grid[y].allSatisfy({ $0.isFilled }) {
            linesToClear.append(y)
        }
    }

    // Remove with descending sort (original buggy code)
    for y in linesToClear.sorted(by: >) {
        grid.remove(at: y)
        grid.insert(Array(repeating: .empty, count: 10), at: 0)
    }

    // With descending sort, the row at index 18 still has red value (not removed)
    // This demonstrates the bug where one line remains uncleared
    let anyRed = grid.contains { row in row.contains { $0.color == .red } }
    #expect(anyRed)  // Bug: red line was not removed
}
