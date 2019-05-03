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
import NIO

internal protocol BNSLoggable { // needs to also be BNSPossiblyQueueable
    // func logTrace(_ message: @escaping @autoclosure () -> Logger.Message)
    // func logDebug(_ message: @escaping @autoclosure () -> Logger.Message)
}

internal protocol BNSEventLoopProtectedLoggable: BNSEventLoopProtectedPossiblyQueueable, BNSLoggable {
    var eventLoopProtectedLogger: Logger? { get }
}

internal extension BNSEventLoopProtectedLoggable {
    func logTrace(_ message: @escaping @autoclosure () -> Logger.Message) {
        self.eventLoop.assertInEventLoop()

        if let logger = self.eventLoopProtectedLogger {
            switch logger.logLevel {
            case .debug, .info, .notice, .warning, .error, .critical:
                break
            case .trace:
                let resolvedMessage = message()
                self.withQueueIfPossible { logger.trace(resolvedMessage) }
            }
        }
    }

    func logDebug(_ message: @escaping @autoclosure () -> Logger.Message) {
        self.eventLoop.assertInEventLoop()

        if let logger = self.eventLoopProtectedLogger {
            switch logger.logLevel {
            case .info, .notice, .warning, .error, .critical:
                break
            case .debug, .trace:
                let resolvedMessage = message()
                self.withQueueIfPossible { logger.debug(resolvedMessage) }
            }
        }
    }
}
