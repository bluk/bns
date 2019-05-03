# Bootstrap Network Services

This library provides a way to bootstrap network services for Swift NIO. It is a currently a copy of a subset of
Apple's [Network framework][network_docs] API on top of Swift NIO's various projects. While this
library tries to mimic some of the behavior described in [WWDC 2018 Session 715][network_wwdc], there
are some differences (and probably bugs in this library).

The main abstractions are a listener (server), connections (from inbound clients), and streams from the connections.
The separation of the connection and the stream allows more granular control than what is present
in some server side frameworks.

For HTTP, a connection represents a socket while a stream represents an individual resource request. One connection
can make multiple resource requests via persistent connections using HTTP/1 or HTTP/2. In HTTP/2, requests can
be multiplexed.

For WebSockets, there is only one stream for a connection.

While some libraries/frameworks are primarily concerned with processing HTTP request/responses, there are some
applications which desire control over the entire client's lifecycle.

Routing, content encoding and decoding, content negotiation, and other related code are not provided. At least for now,
you will either need to build them yourself or use a different library/framework.

## Usage

The latest version of Swift is used for development (currently 5.0.1).

Add the following dependencies to your `Package.swift` file:

```swift
.package(url: "https://github.com/apple/swift-nio.git", from: "2.0.1"),
.package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.2"),
.package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.0.0"),
.package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.0.0"),
.package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
.package(url: "https://github.com/bluk/bns.git", .branch("master")),
```

In your target's dependencies, you will need to add the following:

```swift
.target(
  name: "Your App"
  dependencies: ["NIO", "NIOHTTP1", "NIOExtras", "Logging", "BNS"]
)
```

See the examples in [this repository's `Sources` directory][sources_dir] for code usage.

## Purpose

This is an experimental library used for project spikes with existing Swift code. It is extracted from some common
code used in a few small services. The intention is to provide a package which implements a facade API on top
of Swift NIO, so that Swift server applications and libraries can be easier to bootstrap.

Please feel free to create issues, pull requests, and/or fork the project.

### Initial Design

There were a few requirements kept in mind for the initial design.

First, the library should be a relatively thin layer over Swift NIO. The intention is not to encapsulate Swift NIO
away; the intention is to provide an alternative way to handle common state management without repeatedly wiring up
`ChannelHandler` code. For instance, the connections and streams provide direct access to the `Channel`s and
`EventLoop`s, so it is possible to modify a connection's underlying `ChannelPipeline` among other possible ideas.
If there's an option that can be set on `ServerBootstrap` (or if you want to use the `NIO Transport Services` version
of `ServerBootstrap`), then you should be able to set it without requiring code from this library. If Swift NIO exposes
more functionality, there should be preferably no required changes in this library to expose the new features.

Second, the library should allow processing of inbound and outbound data at a rate your application
controls. The `receive*` and `send*` methods are based on Network.framework's corresponding APIs which make this easier
than some other network APIs.

Third, the library should make working with existing Swift app code relatively easy. Therefore, Grand Central
Dispatch queues are used for dispatching callbacks and are the primary form of concurrency which callers of the
library will need to interact with. One of the reasons why Swift server side is being explored is to re-use existing
Swift skills and code on the server side; most of those skills and code come from an app development's perspective
which primarily uses GCD. Instead of thinking about whether or not each callback implementation is blocking or not,
callbacks are invoked on a dispatch queue (not within any Swift NIO `EventLoop`). While not good for performance,
it is generally the safer choice.

### Production Usage

This library is only an experiment at this point. It is not recommended for any production usage. There are a number
of missing tests for this library, especially for HTTP/2 and WebSocket, and the APIs are not guaranteed to be stable.

## Development

### Debug code

There are branches of the code (which may or may not be in the `master` branch)
which are only enabled with the `DEBUG` flag.

To enable the `DEBUG` compilation flag, run:

```sh
swift build -c debug -Xswiftc ‘-DDEBUG’
```

### Generate Documentation

To generate the documentation, you need Ruby installed, and then run:

```sh
bundle install
swift package generate-xcodeproj
jazzy
```

## Random Quirks

### Starting Connections and Streams

When the new connection handler and new stream handlers are invoked, it is important to set the
properties on the connection/stream and then `start` the connection or stream as soon as
possible:

```swift
listener.newConnectionHandler = { connectionType in
    let connection: BNSBaseConnection = connectionType.baseConnection
    connection.stateUpdateHandler = { state in
        switch state {
        case .setup, .preparing, .ready, .cancelled:
            break
        case .failed:
            connection.cancel()
        }
    }
    switch connectionType {
    case let .http1(httpConnection):
        httpConnection.newStreamHandler = handleHTTPStream
    case .webSocket:
        preconditionFailure("Unexpected WebSocket connection.")
    case .http2:
        preconditionFailure("Unexpected HTTP/2 connection.")
    }
    connection.start(queue: DispatchQueue(label: "AConnectionQueue"))
}
```

While there are no callbacks issued before the `start` method is called, any inbound data for
the connection and/or stream is buffered. Depending on your system, it is not advisible to keep
inbound data buffered for too long. There is a maximum amount of data which can be set in the
configuration options for connections (`maxBufferSizeBeforeConnectionStart`). If the amount of inbound
data exceeds the max size before start on the connection is called, the connection will be closed. There
is no equivalent option for streams.

### States

The listener, connection, and stream types all have state handlers. Usually, you should listen to at least
the `.ready` and `.failed` states. The states normally progress from `.setup` to `.preparing`/`.waiting` to
`.ready`. At any point, you can call `cancel()` and eventually the state will reach the terminal `.cancelled`
state.

All objects must reach the `.cancelled` state before they are `deinit` to ensure resources
will be properly cleaned up. A connection's or stream's underlying `Channel` may be closed, but in order to
cleanup state, the `cancel()` method must be invoked. There are various `assert`s to make sure that you call
cancel before the object is `deinit`.

There is a `.failed(Error)` state as well. This state may be transitioned to at any time. Currently,
you may get multiple `.failed` state transition callbacks with each error that has occurred. You must still
call `cancel()` to transition from `.failed` to `.cancelled`.

### Sending Data

When sending data, there is a `completion` parameter which is of the `BNSStreamSendCompletion` type.
The type has two enum values, `idempotent` and `contentProcessed`.  To stream out data to the underlying channel,
you can do something like:

```swift
func sendMyData() {
  var myData: Data = /* compute some data to send */
  stream.send(content: myData, completion: .contentProcessed { error in
    if let error = error {
      // handle the error
      return
    }

    sendMyData()
  })
}
```

### Sending with Content Contexts and isComplete

In the send methods, there are `contentContext` and `isComplete` parameters which help when multiple
send calls are invoked.

The `contentContext` provides more information about the data being sent (e.g. is this the final content to be sent).

The `isComplete` parameter helps determine when it is ok to write all the content related to the `contentContext`
to the channel. So in practice, if you want to have this library buffer the data to send, you can use the
same `contentContext` instance and `isComplete` set to `false`. When sending the last piece of content, set
`isComplete` to true.

The `contentContext` has object identity equality semantics. So two different instances (which may have the same
property values) are never equal; you must re-use the same object to identify content for the same context.

For instance, here's sending data in stages:

```swift
let dataContext = BNSStreamContentContext(isFinal: true)
var someData: Data = /* ... */
stream.send(
  content: someData,
  contentContext: dataContext,
  isComplete: false,
  completion: .contentProcessed { error in
    /* handle possible error */
    /* note this will not be invoked until some time after the send below with `isComplete` = true is invoked */
  }
)

/* someData is buffered and not written to the channel yet */

/* ... some time later ... */

var someMoreData: Data = /* ... */
stream.send(
  content: someMoreData,
  contentContext: dataContext, /* the same instance */
  isComplete: true,
  completion: .contentProcessed { error in /* handle possible error */ }
)

/* someData and someMoreData are both written due to isComplete = true */
```

There are more properties and features for the `BNSStreamContentContext` which are not written yet.

### Sending with isFinal Content Context

One `BNSStreamContentContext` property is `isFinal`. This indicates this is the last content to send.
In most HTTP request/response cycles, you only have one response content for a stream so when you send content, it
should always have a content context with `isFinal` set to `true`. For HTTP, when `isFinal` is `true` and `isComplete`
is `true` for a send, the HTTP stream will write the content, then any trailing response headers set, and
finish the response.

For normal workflows:

```swift
/* optionally set any trailing HTTP response headers */
var trailerResponseHTTPHeaders = HTTPHeaders()
stream.responseTrailerHeaders = trailerResponseHTTPHeaders

/* send the response */
let finalMessageContext = BNSStreamContentContext(isFinal: true) /* or use BNSStreamContentContext.finalMessage */
var someData: Data = /* ... */
stream.send(
  content: someData,
  contentContext: finalMessageContext,
  isComplete: true,
  completion: .contentProcessed { error in /* handle possible error */ }
)
```

### Logging

The project uses the [swift-log][swift_log] API package. The idea behind logging is to enable a unique `Logger`
to be attached to any connection or any stream at any point. So if you wanted to log streams for a known
set of URIs, you can do so.

For instance, if you want to identify every unique request made from a client connection, you can write:

```swift
import Foundation
/* ... */
var connectionLogger = Logger(label: "Connection1234")
connectionLogger[metadataKey: "connectionID"] = "\(UUID())"
connection.logger = connectionLogger
```

Later in a stream, you can write:

```swift
var streamLogger = connectionLogger
streamLogger[metadataKey: "streamID"] = "\(UInt16.random(in: UInt16.min...UInt16.max))"
stream.logger = streamLogger
```

Due to value type semantics, the connection logger will have (only) the connection ID while the stream logger
will have both the connection ID and the stream ID as contextual logging metadata.

## License

[Apache-2.0 License][license]

[license]: LICENSE
[network_docs]: https://developer.apple.com/documentation/network
[network_wwdc]: https://developer.apple.com/videos/play/wwdc2018/715/
[swift_log]: https://github.com/apple/swift-log
[swift_metrics]: https://github.com/apple/swift-metrics
[sources_dir]: https://github.com/bluk/bns/tree/master/Sources
