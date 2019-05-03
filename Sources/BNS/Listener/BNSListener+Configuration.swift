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

import Logging
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOSSL

/// Declares Configuration.
public extension BNSListener {
    /// Configuration which the listener requires.
    struct Configuration {
        /// The protocols to enable
        public let protocolSupportOptions: ProtocolSupportOptions

        /// The features to enable
        public let featureOptions: FeatureOptions

        /// The TLS configuration to use
        public let tlsConfiguration: TLSConfiguration?

        /// The connection timeout for read
        public let readTimeout: TimeAmount?
        /// The connection timeout for write
        public let writeTimeout: TimeAmount?
        /// The connection timeout for all
        public let allTimeout: TimeAmount?

        /// The maximum number of bytes which should be buffered before a connection is started.
        /// If the number of bytes buffered is greater than the maximum, the underlying channel is
        /// closed.
        /// After the connection is started, it is up to the application to determine
        /// if the request body is too large.
        public let maxBufferSizeBeforeConnectionStart: Int?

        /// The HTTP2 connection settings
        public let http2Settings: [HTTP2Setting]

        /// Designated initializer.
        public init(
            protocolSupportOptions: ProtocolSupportOptions = [.http1],
            featureOptions: FeatureOptions = [],
            tlsConfiguration: TLSConfiguration? = nil,
            readTimeout: TimeAmount? = nil,
            writeTimeout: TimeAmount? = nil,
            allTimeout: TimeAmount? = TimeAmount.minutes(1),
            maxBufferSizeBeforeConnectionStart: Int? = nil,
            http2Settings: [HTTP2Setting] = [
                HTTP2Setting(parameter: .maxConcurrentStreams, value: 100),
                HTTP2Setting(parameter: .maxHeaderListSize, value: 1 << 16),
            ]
        ) {
            precondition(
                protocolSupportOptions.contains(.webSocket) ? protocolSupportOptions.contains(.http1) : true,
                "Need to enable HTTP1 for WebSockets"
            )
            precondition(
                protocolSupportOptions.contains(.http2) ? tlsConfiguration != nil : true,
                "Need to enable TLS for HTTP2"
            )
            self.protocolSupportOptions = protocolSupportOptions
            self.featureOptions = featureOptions
            self.tlsConfiguration = tlsConfiguration
            self.readTimeout = readTimeout
            self.writeTimeout = writeTimeout
            self.allTimeout = allTimeout
            self.maxBufferSizeBeforeConnectionStart = maxBufferSizeBeforeConnectionStart
            self.http2Settings = http2Settings
        }
    }
}
