//// The MIT License (MIT)
//
// Copyright (c) Eclypses, Inc.
//
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import os

// MARK: - PackageLogger Utility
struct PackageLogger {
    static var subsystem = "MteRelay"

    private static var logWriteCount = 0
    
    static func makeLogger(for type: Any.Type) -> LoggerWrapper {
        return LoggerWrapper(for: type)
    }

    static func log(from category: String, level: OSLogType = .info, message: String) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let logger = Logger(subsystem: subsystem, category: category)

        switch level {
        case .info:
            logger.info("\(message, privacy: .public)")
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .fault:
            logger.fault("\(message, privacy: .public)")
        case .default:
            logger.log("\(message, privacy: .public)")
        default:
            logger.log(level: level, "\(message, privacy: .public)")
        }

        if loggingEnabled {
            logToFile("[\(category)][\(level.description.uppercased())] \(message)")
        }
    }

    static var logFileURL: URL? {
        let fm = FileManager.default
        if let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            return dir.appendingPathComponent("relay_debug_log.txt")
        }
        return nil
    }

    static var loggingEnabled: Bool = false

    static func logToFile(_ message: String) {
        guard loggingEnabled, let url = logFileURL else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        let fullMessage = "[\(timestamp)] \(message)\n"

        do {
            let data = fullMessage.data(using: .utf8)!
            if FileManager.default.fileExists(atPath: url.path) {
                let fileHandle = try FileHandle(forWritingTo: url)
                defer { fileHandle.closeFile() }
                try fileHandle.seekToEnd()
                fileHandle.write(data)
            } else {
                try data.write(to: url)
            }
            
            logWriteCount += 1

            if logWriteCount >= 1000 {
                logWriteCount = 0
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? UInt64, fileSize > 1_048_576 {
                    trimLogFile(at: url)
                }
            }
        } catch {
            // Fail silently
        }
    }

    private static func trimLogFile(at url: URL) {
        guard let content = try? String(contentsOf: url) else { return }
        var lines = content.components(separatedBy: .newlines)
        if lines.count > 1000 {
            lines.removeFirst(1000)
            do {
                try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Fail silently
            }
        }
    }
}

struct LoggerWrapper {
    private let category: String

    init(for type: Any.Type) {
        self.category = String(describing: type)
    }

    func info(_ message: String) {
        PackageLogger.log(from: category, level: .info, message: message)
    }

    func debug(_ message: String) {
        PackageLogger.log(from: category, level: .debug, message: message)
    }

    func error(_ message: String) {
        PackageLogger.log(from: category, level: .error, message: message)
    }

    func fault(_ message: String) {
        PackageLogger.log(from: category, level: .fault, message: message)
    }
}

private extension String {
    func appendLine(to url: URL) throws {
        let data = (self + "\n").data(using: .utf8)!
        if FileManager.default.fileExists(atPath: url.path) {
            let fileHandle = try FileHandle(forWritingTo: url)
            defer { fileHandle.closeFile() }
            try fileHandle.seekToEnd()
            fileHandle.write(data)
        } else {
            try write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private extension OSLogType {
    var description: String {
        switch self {
        case .info: return "info"
        case .debug: return "debug"
        case .error: return "error"
        case .fault: return "fault"
        case .default: return "default"
        default: return "unknown"
        }
    }
}

import Foundation

extension NSObject {
    var className: String {
        return String(describing: type(of: self))
    }

    static var className: String {
        return String(describing: self)
    }
}
