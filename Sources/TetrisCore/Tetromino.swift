// Tetromino.swift - Tetromino shape definitions and rendering

import Foundation

public enum TetrominoShape: String, Sendable {
    case I, O, T, S, Z, J, L

    public var blockColor: TetrominoColor {
        switch self {
        case .I:    return .cyan
        case .O:    return .yellow
        case .T:    return .magenta
        case .S:    return .green
        case .Z:    return .red
        case .J:    return .blue
        case .L:    return .orange
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

public struct Tetromino: Sendable {
    public let shape: TetrominoShape
    public let rotationIndex: Int

    public init(shape: TetrominoShape, rotationIndex: Int = 0) {
        self.shape = shape
        self.rotationIndex = rotationIndex
    }

    public var blocks: [[Int]] {
        shape.blocks[(rotationIndex % shape.blocks.count + shape.blocks.count) % shape.blocks.count]
    }

    public func getAbsoluteCoordinates(xOffset: Int, yOffset: Int) -> [(x: Int, y: Int)] {
        blocks.map { (x: xOffset + $0[0], y: yOffset + $0[1]) }
    }

    public func rotated(by offset: Int) -> Tetromino {
        Tetromino(shape: shape, rotationIndex: rotationIndex + offset)
    }
}

/// SRS wall-kick offset tables.
/// Stored as clockwise (CW) transitions. For counter-clockwise use, flip signs.
/// Each entry is [(dx, dy), …] tried in order.
private func cwKickOffsets(for shape: TetrominoShape, fromRotation: Int) -> [(dx: Int, dy: Int)] {
    switch shape {
    case .I:
        switch fromRotation {
        case 0:  return [(0, 0), (-1, 0), (0, -1), (-1, 1), (1, -1), (-2, 0), (0, 2), (-2, -1), (2, 0), (0, -2)]
        case 1:  return [(0, 0), (1, 0), (0, 1), (1, -1), (-1, 1), (2, 0), (0, -2), (2, 1), (-2, 0), (0, 2)]
        case 2:  return [(0, 0), (1, 0), (0, 1), (1, -1), (-1, 1), (2, 0), (0, -2), (2, 1), (-2, 0), (0, 2)]
        default: return [(0, 0), (-1, 0), (0, -1), (-1, 1), (1, -1), (-2, 0), (0, 2), (-2, -1), (2, 0), (0, -2)]
        }
    case .O:
        return [(0, 0)]
    case .T:
        switch fromRotation {
        case 0:  return [(0, 0), (-1, 0), (1, 0), (0, 1), (0, -1), (-1, -1), (1, -1), (-1, 1), (1, 1)]
        case 1:  return [(0, 0), (1, 0), (0, -1), (-1, 0), (0, 1), (1, -1), (-1, 1), (1, 1), (-1, -1)]
        case 2:  return [(0, 0), (-1, 0), (0, 1), (1, 0), (0, -1), (-1, 1), (1, 1), (-1, -1), (1, -1)]
        default: return [(0, 0), (1, 0), (0, 1), (-1, 0), (0, -1), (1, -1), (-1, -1), (1, 1), (-1, 1)]
        }
    default:
        switch fromRotation {
        case 0:  return [(0, 0), (-1, 0), (1, 0), (0, 1), (0, -1), (-1, 1), (1, 1), (-1, -1), (1, -1)]
        case 1:  return [(0, 0), (1, 0), (0, -1), (-1, 0), (0, 1), (1, -1), (-1, -1), (1, 1), (-1, 1)]
        case 2:  return [(0, 0), (-1, 0), (0, 1), (1, 0), (0, -1), (-1, 1), (1, 1), (-1, -1), (1, -1)]
        default: return [(0, 0), (1, 0), (0, 1), (-1, 0), (0, -1), (1, -1), (-1, -1), (1, 1), (-1, 1)]
        }
    }
}

/// Return wall-kick offsets for rotating from `oldRotation` to `newRotation`.
/// Handles both CW and CCW by looking up the stored CW table and flipping signs as needed.
func wallKickOffsets(for shape: TetrominoShape, from oldRotation: Int, to newRotation: Int) -> [(dx: Int, dy: Int)] {
    let stateCount = shape.blocks.count
    let normalizedOld = (oldRotation % stateCount + stateCount) % stateCount
    let normalizedNew = (newRotation % stateCount + stateCount) % stateCount

    // Determine the CW source state for this transition
    let cwSource = (normalizedOld == normalizedNew)
        ? normalizedOld
        : (normalizedNew - normalizedOld + stateCount) % stateCount

    let cwOffsets = cwKickOffsets(for: shape, fromRotation: cwSource)

    // CCW transitions flip signs of the CW table
    let isCCW = (normalizedOld - normalizedNew + stateCount) % stateCount == 1
    return isCCW
        ? cwOffsets.map { (-$0.dx, -$0.dy) }
        : cwOffsets
}
