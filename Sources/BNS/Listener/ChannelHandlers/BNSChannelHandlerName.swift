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

/// The names of the handlers added to the ChannelPipeline
public enum BNSChannelHandlerName: String, CaseIterable {
    /// BackPressureHandler used
    case backPressureHandler = "BNSBackPressureHandler"
    /// IdleStateHandler used
    case idleStateHandler = "BNSIdleStateHandler"
    /// NIOCloseOnErrorHandler used
    case nioCloseOnErrorHandler = "BNSNIOCloseOnErrorHandler"

    /// NIOSSLServerHandler used
    case nioSSLServerHandler = "BNSNIOSSLServerHandler"

    /// HTTPResponseEncoder used
    case httpResponseEncoder = "BNSHTTPResponseEncoder"
    /// ByteToMessageHandler used
    case byteToMessageHandler = "BNSByteToMessageHandler"
    /// BNSHTTP1ConnectionChannelHandler used
    case bnsHTTP1ConnectionChannelHandler = "BNSHTTP1ConnectionChannelHandler"
    /// HTTP1ConnectionBufferChannelHandler used
    case bnsHTTP1ConnectionBufferChannelHandler = "BNSHTTP1ConnectionBufferChannelHandler"
    /// HTTPServerPipelineHandler used
    case httpServerPipelineHandler = "BNSHTTPServerPipelineHandler"
    /// HTTPResponseCompressor used
    case httpResponseCompressor = "BNSHTTPResponseCompressor"
    /// HTTPServerProtocolErrorHandler used
    case httpServerProtocolErrorHandler = "BNSHTTPServerProtocolErrorHandler"
    /// HTTPServerUpgradeHandler used
    case httpServerUpgradeHandler = "BNSHTTPServerUpgradeHandler"
    /// BNSHTTP1StreamChannelHandler used
    case bnsHTTP1StreamChannelHandler = "BNSHTTP1StreamChannelHandler"

    /// NIOHTTP2Handler used
    case nioHTTP2Handler = "BNSNIOHTTP2Handler"
    /// BNSHTTP2ConnectionChannelHandler used
    case bnsHTTP2ConnectionChannelHandler = "BNSHTTP2ConnectionChannelHandler"
    /// BNSHTTP2ConnectionBufferChannelHandler used
    case bnsHTTP2ConnectionBufferChannelHandler = "BNSHTTP2ConnectionBufferChannelHandler"
    /// HTTP2StreamMultiplexer used
    case http2StreamMultiplexer = "BNSHTTP2StreamMultiplexer"

    /// HTTP2ToHTTP1ServerCodec used
    case http2ToHTTP1ServerCodec = "BNSHTTP2ToHTTP1ServerCodec"
    /// BNSHTTP2StreamChannelHandler used
    case bnsHTTP2StreamChannelHandler = "BNSHTTP2StreamChannelHandler"
    /// BNSHTTP2CreatedStreamChannelHandler used
    case bnsHTTP2CreatedStreamChannelHandler = "BNSHTTP2CreatedStreamChannelHandler"

    /// BNSWebSocketConnectionChannelHandler used
    case bnsWebSocketConnectionChannelHandler = "BNSWebSocketConnectionChannelHandler"
    /// BNSWebSocketStreamChannelHandler used
    case bnsWebSocketStreamChannelHandler = "BNSWebSocketStreamChannelHandler"
    /// BNSWebSocketConnectionBufferChannelHandler used
    case bnsWSConnectionBufferChannelHandler = "BNSWebSocketConnectionBufferChannelHandler"
}
