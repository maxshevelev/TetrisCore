// Model/Tetromino.swift

enum TetrominoShape {
    case I, O, T, S, Z, J, L

    var color: String {
        switch self {
        case .I: return Terminal.cyan
        case .O: return Terminal.yellow
        case .T: return Terminal.magenta
        case .S: return Terminal.green
        case .Z: return Terminal.red
        case .J: return Terminal.blue
        case .L: return Terminal.orange
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
                [[0, 1], [1, 1], [2, 1], [1, 2]],
                [[1, 0], [0, 1], [1, 1], [1, 2]]
            ]
        case .L:
            return [
                [[2, 0], [0, 1], [1, 1], [2, 1]],
                [[1, 0], [2, 0], [1, 1], [1, 2]],
                [[0, 1], [1, 1], [2, 1], [0, 2]],
                [[1, 0], [0, 1], [1, 1], [2, 1]]
            ]
        }
    }
}

class Tetromino {
    let shape: TetrominoShape
    var orientation = 0

    init(shape: TetrominoShape) {
        self.shape = shape
    }

    func getAbsoluteCoordinates(xOffset: Int, yOffset: Int) -> [(Int, Int)] {
        return shape.blocks[orientation].map { (xOffset + $0[0], yOffset + $0[1]) }
    }

    func rotate() {
        orientation = (orientation + 1) % shape.blocks.count
    }

    func rotateBack() {
        orientation = (orientation - 1 + shape.blocks.count) % shape.blocks.count
    }
}
