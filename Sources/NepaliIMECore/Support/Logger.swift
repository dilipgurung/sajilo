import Foundation
import os

public enum Log {
    private static let subsystem = "com.gurungdilip.inputmethod.NepaliIME"

    public static let controller = Logger(subsystem: subsystem, category: "controller")
    public static let engine = Logger(subsystem: subsystem, category: "engine")
    public static let learner = Logger(subsystem: subsystem, category: "learner")
    public static let panel = Logger(subsystem: subsystem, category: "panel")
    public static let dict = Logger(subsystem: subsystem, category: "dict")
    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
}
