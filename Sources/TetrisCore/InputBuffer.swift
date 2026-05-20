actor InputBuffer {
    private var buffer: [KeyEvent] = []
    private var continuations: [(KeyEvent) -> Void] = []
    
    func send(_ event: KeyEvent) {
        if let continuation = continuations.first {
            continuations.removeFirst()
            continuation(event)
        } else {
            buffer.append(event)
        }
    }
    
    func receive() async -> KeyEvent {
        if let event = buffer.first {
            buffer.removeFirst()
            return event
        }
        return await withCheckedContinuation { continuation in
            continuations.append { event in
                continuation.resume(returning: event)
            }
        }
    }
}
