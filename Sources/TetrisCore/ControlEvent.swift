// ControlEvent.swift - Abstract user input events
// Source-agnostic: can originate from keyboard, gamepad, gestures, etc.

public enum ControlEvent: Sendable {
    case moveLeft
    case moveRight
    case rotate
    case hardDrop
    case pause
    case resume
    case stop
    case start
}
