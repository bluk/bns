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

import Basic
import Foundation
import NIOSSL
import SPMUtility

/// The server options
public struct EnvironmentOptions {
    let commandLineArguments: CommandLineArguments

    /// The host to bind to
    public var host: String {
        if let host = commandLineArguments.host {
            return host
        }
        var environment = ProcessInfo.processInfo.environment
        if let hostString: String = environment["HOST"] {
            return hostString
        }
        return "127.0.0.1"
    }

    /// The port to bind to
    public var port: Int {
        if let port = commandLineArguments.port {
            return port
        }
        var environment = ProcessInfo.processInfo.environment
        if let portString: String = environment["PORT"], let portInt: Int = Int(portString) {
            return portInt
        }
        return 8888
    }

    /// The path to to the TLS full chain file
    public var tlsCertificateChain: AbsolutePath? {
        if let tlsCertificateChain = commandLineArguments.tlsCertificateChain {
            return tlsCertificateChain
        }
        var environment = ProcessInfo.processInfo.environment
        if let tlsCertificateChain: String = environment["TLS_CERTIFICATE_CHAIN_PATH"] {
            return AbsolutePath(tlsCertificateChain)
        }
        return nil
    }

    /// The path to to the TLS private key file
    public var tlsPrivateKey: AbsolutePath? {
        if let tlsPrivateKey = commandLineArguments.tlsPrivateKey {
            return tlsPrivateKey
        }
        var environment = ProcessInfo.processInfo.environment
        if let tlsPrivateKey: String = environment["TLS_PRIVATE_KEY_PATH"] {
            return AbsolutePath(tlsPrivateKey)
        }
        return nil
    }

    /// If the TLS options are set, attempt to return a TLS configuration
    public var tlsConfiguration: TLSConfiguration? {
        guard let certificateChainPath = self.tlsCertificateChain,
            let privateKeyPath = self.tlsPrivateKey else {
            return nil
        }
        return TLSConfiguration.forServer(
            certificateChain: [.file(certificateChainPath.pathString)],
            privateKey: .file(privateKeyPath.pathString),
            minimumTLSVersion: .tlsv12
        )
    }
}

/// Parses the server options.
public func parseEnvironmentOptions() throws -> EnvironmentOptions {
    return EnvironmentOptions(commandLineArguments: try parseArguments())
}

/// The command line arguments
public struct CommandLineArguments {
    /// The host to bind to
    public var host: String?
    /// The port to bind to
    public var port: Int?
    /// The path to to the TLS full chain file
    public var tlsCertificateChain: AbsolutePath?
    /// The path to to the TLS private key file
    public var tlsPrivateKey: AbsolutePath?
}

/// Parses command line arguments.
public func parseArguments() throws -> CommandLineArguments {
    let argParser = ArgumentParser(
        commandName: CommandLine.arguments.first ?? "Default",
        usage: "<options>",
        overview: "Lauches a server to process HTTP and WebSocket requests."
    )
    let argBinder = ArgumentBinder<CommandLineArguments>()

    argBinder.bind(
        option: argParser.add(option: "--host", kind: String.self, usage: "The host address to bind to"),
        to: { $0.host = $1 }
    )
    argBinder.bind(
        option: argParser.add(option: "--port", kind: Int.self, usage: "The port to bind to"),
        to: { $0.port = $1 }
    )
    argBinder.bind(
        option: argParser.add(
            option: "--tls-certchain",
            kind: PathArgument.self,
            usage: "The path to the certificate chain"
        ),
        to: { $0.tlsCertificateChain = $1.path }
    )
    argBinder.bind(
        option: argParser.add(
            option: "--tls-privatekey",
            kind: PathArgument.self,
            usage: "The path to the private key for the certificate"
        ),
        to: { $0.tlsPrivateKey = $1.path }
    )

    var commandLineArguments = CommandLineArguments()
    let argParseResult = try argParser.parse(Array(CommandLine.arguments.dropFirst()))
    try argBinder.fill(parseResult: argParseResult, into: &commandLineArguments)
    return commandLineArguments
}
