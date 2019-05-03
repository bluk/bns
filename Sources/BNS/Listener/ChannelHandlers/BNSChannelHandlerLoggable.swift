//  Copyright 2019 Bryant Luk
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

import Dispatch
import Logging

internal protocol BNSChannelHandlerLoggable: BNSLoggable {}

internal protocol BNSOnlyLoggerChannelHandlerLoggable: BNSChannelHandlerLoggable {
    var logger: Logger? { get }
}

internal extension BNSOnlyLoggerChannelHandlerLoggable where Self: BNSOnlyQueuePossiblyQueueable {
    func logTrace(_ message: @escaping @autoclosure () -> Logger.Message) {
        if var logger = self.logger {
            switch logger.logLevel {
            case .debug, .info, .notice, .warning, .error, .critical:
                break
            case .trace:
                logger[metadataKey: "handler"] = "\(type(of: self))"
                let resolvedMessage = message()
                self.withQueueIfPossible { logger.trace(resolvedMessage) }
            }
        }
    }

    func logDebug(_ message: @escaping @autoclosure () -> Logger.Message) {
        if var logger = self.logger {
            switch logger.logLevel {
            case .info, .notice, .warning, .error, .critical:
                break
            case .debug, .trace:
                logger[metadataKey: "handler"] = "\(type(of: self))"
                let resolvedMessage = message()
                self.withQueueIfPossible { logger.debug(resolvedMessage) }
            }
        }
    }

    func logError(_ message: @escaping @autoclosure () -> Logger.Message) {
        if var logger = self.logger {
            switch logger.logLevel {
            case .trace, .debug, .info, .notice, .warning, .critical:
                break
            case .error:
                logger[metadataKey: "handler"] = "\(type(of: self))"
                let resolvedMessage = message()
                self.withQueueIfPossible { logger.error(resolvedMessage) }
            }
        }
    }
}

internal protocol BNSWithLoggableInstanceChannelHandlerLoggable: BNSChannelHandlerLoggable {
    associatedtype Loggable: BNSEventLoopProtectedLoggable

    var eventLoopProtectedLoggable: Loggable? { get }
}

internal extension BNSWithLoggableInstanceChannelHandlerLoggable {
    func logTrace(_ message: @escaping @autoclosure () -> Logger.Message) {
        if let eventLoopProtectedLoggable = eventLoopProtectedLoggable {
            eventLoopProtectedLoggable.eventLoop.assertInEventLoop()

            if var logger = eventLoopProtectedLoggable.eventLoopProtectedLogger {
                switch logger.logLevel {
                case .debug, .info, .notice, .warning, .error, .critical:
                    break
                case .trace:
                    logger[metadataKey: "handler"] = "\(type(of: self))"
                    let resolvedMessage = message()
                    eventLoopProtectedLoggable.withQueueIfPossible { logger.trace(resolvedMessage) }
                }
            }
        }
    }

    func logDebug(_ message: @escaping @autoclosure () -> Logger.Message) {
        if let eventLoopProtectedLoggable = eventLoopProtectedLoggable {
            eventLoopProtectedLoggable.eventLoop.assertInEventLoop()

            if var logger = eventLoopProtectedLoggable.eventLoopProtectedLogger {
                switch logger.logLevel {
                case .info, .notice, .warning, .error, .critical:
                    break
                case .debug, .trace:
                    logger[metadataKey: "handler"] = "\(type(of: self))"
                    let resolvedMessage = message()
                    eventLoopProtectedLoggable.withQueueIfPossible { logger.debug(resolvedMessage) }
                }
            }
        }
    }
}
