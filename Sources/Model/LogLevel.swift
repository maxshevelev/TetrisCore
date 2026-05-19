import os

public enum LogLevel: String, CaseIterable, Sendable {
    case debug, info, notice, error, fault

    private var order: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .notice: return 2
        case .error: return 3
        case .fault: return 4
        }
    }

    public func allows(_ level: LogLevel) -> Bool {
        self.order <= level.order
    }

    public var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }
}
