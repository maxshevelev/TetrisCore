// ConsoleInputHandler.swift - Non-blocking stdin reader using dispatch queue

import Darwin
import Foundation
import Model

class ConsoleInputHandler: @unchecked Sendable {
    private let inputQueue = DispatchQueue(label: "input.queue")
    private var originalTermios = termios()
    private var running = false

    private weak var inputReceiver: InputReceiver?

    func setInputReceiver(_ receiver: InputReceiver) {
        self.inputReceiver = receiver
    }

    init() {
        enableRawMode()
    }

    deinit {
        disableRawMode()
    }

    func start() {
        running = true
        inputQueue.async { [weak self] in
            guard let self = self else { return }
            while self.running {
                var byte: UInt8 = 0
                let n = read(STDIN_FILENO, &byte, 1)
                if n == 1 {
                    self.processByte(byte)
                }
                usleep(10000)
            }
        }
    }

    func stop() {
        running = false
        // Wait for input queue to finish processing
        inputQueue.sync {}
    }

    func cleanup() {
        disableRawMode()
    }

    private func processByte(_ byte: UInt8) {
        let scalar = UnicodeScalar(byte)
        let char = Character(scalar)

        switch char {
        case "j": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.moveLeft) }
        case "l": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.moveRight) }
        case "k": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.rotate) }
        case " ": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.hardDrop) }
        case "\u{1b}": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.esc) }
        case "q": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.quit) }
        default: break
        }
    }

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON) | UInt(ISIG) | UInt(IEXTEN))
        raw.c_iflag &= ~(UInt(IXON) | UInt(ICRNL) | UInt(BRKINT) | UInt(INPCK) | UInt(ISTRIP))
        raw.c_oflag &= ~(UInt(OPOST))
        raw.c_cflag |= UInt(CS8)
        raw.c_cc.16 = 1  // VMIN
        raw.c_cc.17 = 0  // VTIME
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    private func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
    }
}
