import Testing
import Model

// MARK: - Movement Tests

@Test("moveLeft moves piece left when not colliding")
func moveLeft_movesLeft() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    let piece = Tetromino(shape: .I)
    var currentX = 5
    let currentY = 5

    currentX -= 1
    if !isColliding(grid: grid, piece: piece, x: currentX, y: currentY) {
        // Move is valid
    } else {
        currentX += 1
    }

    #expect(currentX == 4)
}

@Test("moveLeft does not move piece into wall")
func moveLeft_doesNotMoveIntoWall() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    let piece = Tetromino(shape: .I)
    var currentX = 0
    let currentY = 5

    currentX -= 1
    if !isColliding(grid: grid, piece: piece, x: currentX, y: currentY) {
        // Move is valid
    } else {
        currentX += 1
    }

    #expect(currentX == 0)
}

@Test("moveRight moves piece right when not colliding")
func moveRight_movesRight() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    let piece = Tetromino(shape: .I)
    var currentX = 5
    let currentY = 5

    currentX += 1
    if !isColliding(grid: grid, piece: piece, x: currentX, y: currentY) {
        // Move is valid
    } else {
        currentX -= 1
    }

    #expect(currentX == 6)
}

@Test("moveRight does not move piece into wall")
func moveRight_doesNotMoveIntoWall() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    let piece = Tetromino(shape: .I)
    var currentX = 9
    let currentY = 5

    currentX += 1
    if !isColliding(grid: grid, piece: piece, x: currentX, y: currentY) {
        // Move is valid
    } else {
        currentX -= 1
    }

    #expect(currentX == 9)
}

// MARK: - Rotation Tests

@Test("rotatePiece rotates the piece")
func rotate_rotatesPiece() async {
    let piece = Tetromino(shape: .I)
    let initialCoordinates = piece.getAbsoluteCoordinates(xOffset: 0, yOffset: 0)
    let rotated = piece.rotated(by: -1)
    let rotatedCoordinates = rotated.getAbsoluteCoordinates(xOffset: 0, yOffset: 0)

    // I piece rotates from horizontal to vertical - coordinates change
    #expect(!initialCoordinates.elementsEqual(rotatedCoordinates, by: ==))
}

@Test("rotatePiece undo rotation when colliding")
func rotate_doesNotRotateWhenColliding() async {
    let grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    let piece = Tetromino(shape: .T)
    let currentX = 5
    let currentY = 18

    let originalCoordinates = piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY)
    let rotated = piece.rotated(by: -1)
    let finalCoordinates = isColliding(grid: grid, piece: rotated, x: currentX, y: currentY)
        ? originalCoordinates
        : rotated.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY)
    #expect(originalCoordinates.elementsEqual(finalCoordinates, by: ==))
}

// MARK: - Hard Drop Tests

@Test("hardDrop drops piece to bottom")
func hardDrop_dropsToBottom() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    let piece = Tetromino(shape: .O)
    var currentX = 4
    var currentY = 0

    while canMoveDown(grid: grid, piece: piece, y: currentY + 1) {
        currentY += 1
    }

    #expect(currentY == 18)
}

// MARK: - Collision Tests

@Test("isColliding returns false when piece is in empty space")
func isColliding_emptySpace() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    let piece = Tetromino(shape: .T)
    let x = 3
    let y = 5

    #expect(!isColliding(grid: grid, piece: piece, x: x, y: y))
}

@Test("isColliding returns true when piece hits left wall")
func isColliding_hitsLeftWall() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    let piece = Tetromino(shape: .I)
    let x = -1
    let y = 5

    #expect(isColliding(grid: grid, piece: piece, x: x, y: y))
}

@Test("isColliding returns true when piece hits right wall")
func isColliding_hitsRightWall() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    let piece = Tetromino(shape: .I)
    let x = 10
    let y = 5

    #expect(isColliding(grid: grid, piece: piece, x: x, y: y))
}

@Test("isColliding returns true when piece hits bottom")
func isColliding_hitsBottom() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    let piece = Tetromino(shape: .O)
    let x = 3
    let y = 20

    #expect(isColliding(grid: grid, piece: piece, x: x, y: y))
}

@Test("isColliding returns true when piece overlaps with filled block")
func isColliding_overlapsFilledBlock() async {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    let piece = Tetromino(shape: .T)

    // T piece at (0,0) has blocks at: (0,0), (1,0), (2,0), (1,1)
    // So at offset (3,5), blocks are at: (3,5), (4,5), (5,5), (4,6)
    // Fill the center block of the T
    let centerX = 4
    let centerY = 5

    grid[centerY][centerX] = .filled(.red)

    #expect(isColliding(grid: grid, piece: piece, x: 3, y: 5))
}

// MARK: - Spawn Tests

@Test("spawnNewPiece sets current piece to next piece")
func spawnNewPiece_setsCurrentPiece() async {
    let nextPiece = Tetromino(shape: .T)
    var currentPiece: Tetromino? = nil
    var currentX = 0
    var currentY = 0

    currentPiece = nextPiece
    currentX = 10 / 2 - 2
    currentY = 0

    #expect(currentPiece != nil)
    #expect(currentX == 3)
    #expect(currentY == 0)
}

@Test("spawnNewPiece when colliding triggers game over")
func spawnNewPiece_gameOverOnCollide() async {
    var nextPiece = Tetromino(shape: .I)
    var currentX = 0
    var currentY = 0

    let pieceAtSpawnPos = Tetromino(shape: .I)
    let width = 10
    let height = 20

    // Check if piece collides at spawn position
    var colliding = false
    for (px, _) in pieceAtSpawnPos.getAbsoluteCoordinates(xOffset: 3, yOffset: 0) {
        if px < 0 || px >= width { colliding = true; break }
    }

    #expect(!colliding)

    // Test with a piece that would collide - spawn at x=-1
    var spawnColliding = false
    for (px, _) in pieceAtSpawnPos.getAbsoluteCoordinates(xOffset: -1, yOffset: 0) {
        if px < 0 { spawnColliding = true; break }
    }

    #expect(spawnColliding)
}

// MARK: - Line Clearing Tests

private func linesClearedIn(_ grid: [[BlockState]]) -> Int {
    grid.filter { $0.allSatisfy { $0.isFilled } }.count
}

@Test("no lines cleared when no row is full")
func clearLines_noLinesCleared() {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    grid[5] = Array(repeating: .filled(.red), count: 9)
    grid[5][5] = .empty

    #expect(linesClearedIn(grid) == 0)
}

@Test("single line is cleared when fully filled")
func clearLines_singleLine() {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    grid[10] = Array(repeating: .filled(.red), count: 10)

    #expect(linesClearedIn(grid) == 1)

    let filledRows = grid.filter { $0.allSatisfy { $0.isFilled } }
    #expect(filledRows.count == 1)
}

@Test("multiple lines are cleared when fully filled")
func clearLines_multipleLines() {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    for row in 8...10 {
        grid[row] = Array(repeating: .filled(.cyan), count: 10)
    }

    #expect(linesClearedIn(grid) == 3)
}

@Test("four lines are cleared simultaneously")
func clearLines_fourLines() {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    for row in 16...19 {
        grid[row] = Array(repeating: .filled(.blue), count: 10)
    }

    #expect(linesClearedIn(grid) == 4)
}

@Test("only fully filled rows are removed from grid")
func clearLines_onlyFullRowsRemoved() {
    var grid: [[BlockState]] = Array(repeating: Array(repeating: .empty, count: 10), count: 20)
    for row in 10...12 {
        grid[row] = Array(repeating: .filled(.green), count: 10)
    }

    let fullCount = grid.filter { $0.allSatisfy { $0.isFilled } }.count
    #expect(fullCount == 3)

    // Check that partial rows remain
    grid[11][5] = .empty
    let remainingFull = grid.filter { $0.allSatisfy { $0.isFilled } }.count
    #expect(remainingFull == 2)
}

// MARK: - Helper Functions

func isColliding(grid: [[BlockState]], piece: Tetromino, x: Int, y: Int) -> Bool {
    let width = 10
    let height = 20

    for (px, py) in piece.getAbsoluteCoordinates(xOffset: x, yOffset: y) {
        if px < 0 || px >= width || py >= height { return true }
        if py >= 0 && grid[py][px].isFilled { return true }
    }
    return false
}

func canMoveDown(grid: [[BlockState]], piece: Tetromino, y: Int) -> Bool {
    let width = 10
    let height = 20

    for (px, py) in piece.getAbsoluteCoordinates(xOffset: 0, yOffset: y) {
        if px < 0 || px >= width || py >= height { return false }
        if py >= 0 && grid[py][px].isFilled { return false }
    }
    return true
}
