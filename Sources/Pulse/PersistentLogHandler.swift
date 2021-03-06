// The MIT License (MIT)
//
// Copyright (c) 2020 Alexander Grebenyuk (github.com/kean).

import CoreData
import Foundation
import Logging

public struct PersistentLogHandler {
    public var metadata = Logger.Metadata()
    public var logLevel = Logger.Level.info

    /// An id of the current log sesion.
    public static private(set) var logSessionId = UUID()

    private let store: LoggerMessageStore
    private let makeCurrentDate: () -> Date

    private let label: String

    public init(label: String) {
        self.init(label: label, store: .default)
    }

    public init(label: String, store: LoggerMessageStore) {
        self.label = label
        self.store = store
        self.makeCurrentDate = Date.init
    }

    init(label: String, store: LoggerMessageStore, makeCurrentDate: @escaping () -> Date) {
        self.label = label
        self.store = store
        self.makeCurrentDate = makeCurrentDate
    }
}

extension PersistentLogHandler: LogHandler {
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            metadata[key]
        } set(newValue) {
            metadata[key] = newValue
        }
    }

    /// Starts a new log session.
    @discardableResult
    public static func startSession() -> UUID {
        logSessionId = UUID()
        return logSessionId
    }

    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {
        let context = store.backgroundContext
        let date: Date
        if let metadata = metadata, case let .stringConvertible(value)? = metadata[NetworkLoggerMetadataKey.createdAt], let customDate = value as? Date {
            date = customDate
        } else {
            date = makeCurrentDate()
        }
        let label = self.label

        context.perform {
            let entity = MessageEntity(context: context)
            entity.createdAt = date
            entity.level = level.rawValue
            entity.label = label
            entity.session = Self.logSessionId.uuidString
            entity.text = String(describing: message)
            if let entries = metadata?.unpack(), !entries.isEmpty {
                entity.metadata = Set(entries.compactMap { key, value in
                    guard key != NetworkLoggerMetadataKey.createdAt else { return nil }
                    let entity = MetadataEntity(context: context)
                    entity.key = key
                    entity.value = value
                    return entity
                })
            }
            entity.file = file
            entity.function = function
            entity.line = Int32(line)
            try? context.save()
        }
    }
}

private extension Logger.Metadata {
    func unpack() -> [(String, String)] {
        var entries = [(String, String)]()
        for (key, value) in self {
            switch value {
            case let .string(string):
                entries.append((key, string))
            case let .stringConvertible(string):
                entries.append((key, string.description))
            default:
                break // Skip other types
            }
        }
        return entries
    }
}
