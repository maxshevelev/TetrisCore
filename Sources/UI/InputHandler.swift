// UI/InputHandler.swift

import Foundation

class InputHandler {
    var lastChar: Character?
    let inputQueue = DispatchQueue(label: "input.queue")
    var originalTermios = termios()

    init() {
        enableRawMode()
        startListening()
    }

    deinit {
        disableRawMode()
        print(Terminal.showCursor)
    }

    func enableRawMode() {
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON) | UInt(ISIG) | UInt(IEXTEN))
        raw.c_iflag &= ~(UInt(IXON) | UInt(ICRNL) | UInt(BRKINT) | UInt(INPCK) | UInt(ISTRIP))
        raw.c_oflag &= ~(UInt(OPOST))
        raw.c_cflag |= UInt(CS8)
        raw.c_cc.16 = 1
        raw.c_cc.17 = 0
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
    }

    func startListening() {
        inputQueue.async {
            while true {
                var byte: UInt8 = 0
                let n = read(STDIN_FILENO, &byte, 1)
                if n == 1 {
                    let scalar = UnicodeScalar(byte)
                    self.lastChar = Character(scalar)
                }
                usleep(10000)
            }
        }
    }

    func getInput() -> Character? {
        let input = lastChar
        lastChar = nil
        return input
    }
}