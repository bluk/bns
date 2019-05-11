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
import NIOSSL

internal extension ChannelPipeline {
    // swiftlint:disable function_body_length

    func configureProtocolsWithTLS(
        context: BNSListener.InitializeChildChannelContext,
        tlsConfig: TLSConfiguration
    ) -> EventLoopFuture<Void> {
        do {
            let sslContext: NIOSSLContext = try NIOSSLContext(configuration: tlsConfig)
            let sslServerHandler: NIOSSLServerHandler = try NIOSSLServerHandler(context: sslContext)

            return self.addHandler(sslServerHandler, name: BNSChannelHandlerName.nioSSLServerHandler.rawValue)
                .flatMap {
                    let configurePromise: EventLoopPromise<Void> = context.channel.eventLoop.makePromise()

                    context.queue.async {
                        if context.configuration.protocolSupportOptions.contains(.http2) {
                            self.configureHTTP2SecureUpgrade(
                                h2PipelineConfigurator: { pipeline in
                                    let h2ConfigurePromise: EventLoopPromise<Void>
                                        = context.channel.eventLoop.makePromise()
                                    context.queue.async {
                                        let finishPipelineInitPromise: EventLoopPromise<Void>
                                            = context.channel.eventLoop.makePromise()
                                        let addHandlersFuture = pipeline.configureH2(
                                            context: context,
                                            finishPipelineInitFuture: finishPipelineInitPromise.futureResult
                                        )
                                        .flatMap { () -> EventLoopFuture<Void> in
                                            pipeline.addHandler(
                                                NIOCloseOnErrorHandler(),
                                                name: BNSChannelHandlerName.nioCloseOnErrorHandler.rawValue
                                            )
                                        }

                                        addHandlersFuture.whenComplete { _ in
                                            finishPipelineInitPromise.succeed(())
                                        }

                                        addHandlersFuture.cascade(to: h2ConfigurePromise)
                                    }
                                    return h2ConfigurePromise.futureResult
                                },
                                http1PipelineConfigurator: { pipeline in
                                    if context.configuration.protocolSupportOptions.contains(.http1) {
                                        return pipeline.configureHTTP1WithError(
                                            context: context
                                        )
                                    } else {
                                        return context.channel.close().flatMap {
                                            context.channel.eventLoop.makeFailedFuture(
                                                BNSListenerError.unsupportedProtocol
                                            )
                                        }
                                    }
                                }
                            )
                            .cascade(to: configurePromise)
                            return
                        } else if context.configuration.protocolSupportOptions.contains(.http1) {
                            self.configureHTTP1WithError(context: context)
                                .cascade(to: configurePromise)
                            return
                        } else {
                            context.channel.close()
                                .flatMap {
                                    context.channel.eventLoop.makeFailedFuture(BNSListenerError.unsupportedProtocol)
                                }
                                .cascade(to: configurePromise)
                            return
                        }
                    }

                    return configurePromise.futureResult
                }
        } catch {
            return context.channel.close().flatMap {
                context.channel.eventLoop.makeFailedFuture(error)
            }
        }
    }

    // swiftlint:enable function_body_length
}
