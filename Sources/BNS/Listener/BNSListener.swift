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
import NIOHTTP1
import NIOHTTP2
import NIOSSL
import NIOWebSocket

/// If the HTTP connection should be upgraded to a WebSocket.
public typealias BNSHTTPShouldUpgradeToWebSocketHandler
    = (HTTPRequestHead, @escaping (Result<HTTPHeaders, Error>) -> Void) -> Void

/// A bootstrapped network server. It listens and accepts requests for standard web protocols.
/// A listener should be created, the `bootstrapChannelHandler`, `stateUpdateHandler`,
/// and `newConnectionHandler` should at least be set, and then the listener can be started.
public final class BNSListener {
    /// The configuration
    public let configuration: Configuration

    /// The queue where all the handler callbacks will be dispatched on.
    public private(set) var queue: DispatchQueue?

    /// The current state of the instance. Must be accessed on the
    /// callback dispatch queue.
    public internal(set) var state: State = .setup

    private var queueProtectedInternalState: InternalState = InternalState()

    /// Handler for state changes. In general, the handler should listen to at least the `failed` state to
    /// transition and `cancel` the listener. The update to `cancelled` state can also be used as
    /// a way to cleanup any outstanding resources.
    ///
    /// An example for how to set this handler:
    ///
    ///
    /// ```
    /// listener.stateUpdateHandler = { state in
    ///   switch state {
    ///     case let .failed(error):
    ///       print(error)
    ///       listener.cancel()
    ///     default:
    ///       break
    ///   }
    /// }
    /// ```
    public var stateUpdateHandler: ((State) -> Void)?

    /// Bootstraps the server listener. The handler is given a closure parameter to call in
    /// the `childChannelInitializer` for a ServerBootstrap.
    ///
    /// The handler is called after the `start(queue: DispatchQueue)` method is invoked.
    ///
    /// The caller is given the flexibility to set any server channel and child channel options desired or
    /// using a different NIO bootstrap method (such as using the NIOTransportServices).
    ///
    /// An example for how to set this handler:
    ///
    /// ```
    /// listener.bootstrapChannelHandler = { childChannelInitializer in
    ///   return ServerBootstrap(group: eventLoopGroup)
    ///     .serverChannelOption(ChannelOptions.backlog, value: 256)
    ///     .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    ///     .childChannelInitializer { channel in
    ///         childChannelInitializer(channel)
    ///     }
    ///     .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
    ///     .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    ///     .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
    ///     .bind(host: "127.0.0.1", port: 8080)
    /// }
    /// ```
    public var bootstrapChannelHandler: ((@escaping (Channel) -> EventLoopFuture<Void>) -> EventLoopFuture<Channel>)?

    /// Handler for new connections. Must be accessed on the callback dispatch queue. The connection's properties should
    /// be set and then the connection should be started.
    ///
    /// ```
    /// listener.newConnectionHandler = { connection in
    ///   switch connection {
    ///     case let .http1(httpConection):
    ///       httpConnection.stateUpdateHandler = ...
    ///       httpConnection.newStreamHandler = ...
    ///       httpConnection.start()
    ///     case let .http2(httpConection):
    ///       httpConnection.stateUpdateHandler = ...
    ///       httpConnection.newStreamHandler = ...
    ///       httpConnection.start()
    ///     case .webSocket:
    ///       break
    ///   }
    /// }
    /// ```
    public var newConnectionHandler: (BNSConnectionHandler)?

    /// The logger to use. Must be accessed on the callback dispatch queue.
    public var logger: Logger?

    /// The channel for the listener. Must be accessed on the callback dispatch queue.
    public private(set) var channel: Channel?

    private var isCancelCalled: Bool = false

    /// Designated initializer.
    ///
    /// - Parameters:
    ///     - configuration: The listener's configuration.
    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// The deinit for the listener.
    deinit {
        self.queueProtectedInternalState.assertDeinit()
        assert(!(channel?.isActive ?? false), "Channel is still active.")
        self.logger?.trace("deinit")
    }

    /// Starts the listener. The listener should have its handlers and other options set before
    /// invoking this method. The `stateUpdateHandler` will be notified when the listener
    /// is ready to process connections.
    ///
    /// - Parameters:
    ///     - queue: The queue to use for callbacks.
    public final func start(queue: DispatchQueue) {
        queue.async {
            guard !self.isCancelCalled else {
                assertionFailure("Should not call start() after calling cancel().")
                return
            }

            guard self.queue == nil else {
                assertionFailure("Should not call start() twice.")
                return
            }
            self.queue = queue

            self.logger?.trace("start(queue:) called")

            self.queueProtectedInternalState.assertStart()

            self.queueProtectedInternalState.transition(to: .waiting, on: self)

            let childChannelInitializer: (Channel) -> EventLoopFuture<Void> = { [weak self] channel in
                guard let self = self else {
                    return channel.close().flatMap {
                        channel.eventLoop.makeFailedFuture(BNSListenerError.invalidState)
                    }
                }

                return self.initializeChildChannel(channel: channel)
            }

            guard let bootstrapChannelHandler = self.bootstrapChannelHandler else {
                preconditionFailure("bootstrapChannelHandler must be set.")
            }

            bootstrapChannelHandler(childChannelInitializer)
                .whenComplete { result in
                    switch result {
                    case let .success(value):
                        queue.async {
                            self.channel = value
                            self.queueProtectedInternalState.transition(to: .ready, on: self)
                        }
                    case let .failure(error):
                        queue.async {
                            self.queueProtectedInternalState.transition(to: .failed(error), on: self)
                        }
                    }
                }
        }
    }

    // swiftlint:disable function_body_length

    private final func initializeChildChannel(channel: Channel) -> EventLoopFuture<Void> {
        guard let queue = self.queue else {
            preconditionFailure("Should have had a queue set.")
        }

        return channel.pipeline.addHandler(
            BackPressureHandler(),
            name: BNSChannelHandlerName.backPressureHandler.rawValue
        )
        .flatMap { _ in
            channel.pipeline.addHandler(
                IdleStateHandler(
                    readTimeout: self.configuration.readTimeout,
                    writeTimeout: self.configuration.writeTimeout,
                    allTimeout: self.configuration.allTimeout
                ),
                name: BNSChannelHandlerName.idleStateHandler.rawValue
            )
        }
        .flatMap { _ in
            let promise: EventLoopPromise<Void> = channel.eventLoop.makePromise()
            queue.async {
                let initializeChildChannelContext = InitializeChildChannelContext(
                    channel: channel,
                    queue: queue,
                    newConnectionHandler: self.wrappedNewConnectionHandler(queue: queue),
                    configuration: self.configuration,
                    logger: self.logger
                )

                switch self.state {
                case .setup, .waiting, .cancelled, .failed:
                    channel.close()
                        .flatMap { channel.eventLoop.makeFailedFuture(BNSListenerError.invalidState) }
                        .cascade(to: promise)
                    return
                case .ready:
                    break
                }

                guard var tlsConfig = self.configuration.tlsConfiguration else {
                    channel.pipeline.configureHTTP1WithError(context: initializeChildChannelContext)
                        .cascade(to: promise)
                    return
                }

                if self.configuration.protocolSupportOptions.contains(.http2) {
                    tlsConfig.applicationProtocols.append("h2")
                }
                if self.configuration.protocolSupportOptions.contains(.http1) {
                    tlsConfig.applicationProtocols.append("http/1.1")
                }

                channel.pipeline.configureProtocolsWithTLS(
                    context: initializeChildChannelContext,
                    tlsConfig: tlsConfig
                )
                .cascade(to: promise)
            }

            return promise.futureResult
        }
    }

    // swiftlint:enable function_body_length

    private final func wrappedNewConnectionHandler(queue: DispatchQueue) -> BNSConnectionHandler {
        return { (connection: BNSConnection) -> Void in
            queue.async { [weak self] in
                guard let self = self else {
                    connection.baseConnection.cancel()
                    return
                }
                guard let newConnectionHandler = self.newConnectionHandler else {
                    connection.baseConnection.cancel()
                    return
                }
                newConnectionHandler(connection)
            }
        }
    }

    /// Asks to cancel the listener and attempts to stop processing.
    ///
    /// The listener is completely cancelled when the state changes in the `stateUpdateHandler`.
    public final func cancel() {
        let queue: DispatchQueue = self.queue ?? BNSDefaultCallbackQueue

        queue.async {
            guard !self.isCancelCalled else {
                return
            }

            self.isCancelCalled = true

            self.bootstrapChannelHandler = nil
            self.newConnectionHandler = nil

            guard let channel = self.channel else {
                queue.async {
                    self.queueProtectedInternalState.transition(to: .cancelled, on: self)
                    self.stateUpdateHandler = nil
                }
                return
            }

            channel.closeFuture.whenComplete { _ in
                queue.async {
                    self.queueProtectedInternalState.transition(to: .cancelled, on: self)
                    self.stateUpdateHandler = nil
                }
            }
            _ = channel.close()
        }
    }
}
