// Tetromino.swift - Tetromino shape definitions and rendering

import Foundation

enum TetrominoShape: String {
    case I, O, T, S, Z, J, L

    var color: String {
        switch self {
        case .I: return "\u{001B}[36m"  // Cyan
        case .O: return "\u{001B}[33m"  // Yellow
        case .T: return "\u{001B}[35m"  // Magenta
        case .S: return "\u{001B}[32m"  // Green
        case .Z: return "\u{001B}[31m"  // Red
        case .J: return "\u{001B}[34m"  // Blue
        case .L: return "\u{001B}[38;5;208m"  // Orange
        }
    }

    var blocks: [[[Int]]] {
        switch self {
        case .I:
            return [
                [[0, 1], [1, 1], [2, 1], [3, 1]],
                [[1, 0], [1, 1], [1, 2], [1, 3]]
            ]
        case .O:
            return [[[1, 0], [2, 0], [1, 1], [2, 1]]]
        case .T:
            return [
                [[1, 0], [0, 1], [1, 1], [2, 1]],
                [[1, 0], [1, 1], [2, 1], [1, 2]],
                [[0, 1], [1, 1], [2, 1], [1, 2]],
                [[1, 0], [0, 1], [1, 1], [1, 2]]
            ]
        case .S:
            return [
                [[1, 0], [2, 0], [0, 1], [1, 1]],
                [[1, 0], [1, 1], [2, 1], [2, 2]]
            ]
        case .Z:
            return [
                [[0, 0], [1, 0], [1, 1], [2, 1]],
                [[2, 0], [1, 1], [2, 1], [1, 2]]
            ]
        case .J:
            return [
                [[0, 0], [0, 1], [1, 1], [2, 1]],
                [[1, 0], [2, 0], [1, 1], [1, 2]],
                [[0, 1], [1, 1], [2, 1], [2, 2]],
                [[1, 0], [1, 1], [1, 2], [0, 2]]
            ]
        case .L:
            return [
                [[2, 0], [0, 1], [1, 1], [2, 1]],
                [[1, 0], [1, 1], [1, 2], [2, 2]],
                [[0, 1], [1, 1], [2, 1], [0, 2]],
                [[0, 0], [1, 0], [1, 1], [1, 2]]
            ]
        }
    }
}

class Tetromino {
    let shape: TetrominoShape
    private var _rotationIndex = 0

    init(shape: TetrominoShape) {
        self.shape = shape
    }

    var rotationIndex: Int {
        (_rotationIndex % shape.blocks.count + shape.blocks.count) % shape.blocks.count
    }

    var blocks: [[Int]] {
        shape.blocks[rotationIndex]
    }

    func getAbsoluteCoordinates(xOffset: Int, yOffset: Int) -> [(x: Int, y: Int)] {
        return blocks.map { block in
            (x: xOffset + block[0], y: yOffset + block[1])
        }
    }

    func rotate() {
        _rotationIndex -= 1
    }

    func rotateBack() {
        _rotationIndex += 1
    }

    func clone() -> Tetromino {
        let clone = Tetromino(shape: shape)
        clone._rotationIndex = _rotationIndex
        return clone
    }
}
