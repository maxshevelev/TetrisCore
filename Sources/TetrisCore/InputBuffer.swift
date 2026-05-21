actor InputBuffer {
    private var buffer: [ControlEvent] = []
    private var continuations: [(ControlEvent) -> Void] = []

    func send(_ event: ControlEvent) {
        if let continuation = continuations.first {
            continuations.removeFirst()
            continuation(event)
        } else {
            buffer.append(event)
        }
    }

    func receive() async -> ControlEvent {
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
