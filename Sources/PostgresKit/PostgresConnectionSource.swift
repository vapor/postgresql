public struct PostgresConnectionSource: ConnectionPoolSource {
    public let configuration: PostgresConfiguration

    public init(configuration: PostgresConfiguration) {
        self.configuration = configuration
    }

    public func makeConnection(
        logger: Logger,
        on eventLoop: EventLoop
    ) -> EventLoopFuture<PostgresConnection> {
        let address: SocketAddress
        do {
            address = try self.configuration.address()
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
        return PostgresConnection.connect(
            to: address,
            tlsConfiguration: self.configuration.tlsConfiguration,
            serverHostname: self.configuration._hostname,
            logger: logger,
            on: eventLoop
        ).flatMap { conn in
            return conn.authenticate(
                username: self.configuration.username,
                database: self.configuration.database,
                password: self.configuration.password,
                logger: logger
            ).flatMap {
                if let searchPath = self.configuration.searchPath {
                    let string = searchPath.map { "\"" + $0 + "\"" }.joined(separator: ", ")
                    return conn.simpleQuery("SET search_path = \(string)")
                        .map { _ in }
                } else {
                    return eventLoop.makeSucceededFuture(())
                }
            }.flatMapErrorThrowing { error in
                _ = conn.close()
                throw error
            }.map { conn }
        }
    }
}

extension PostgresConnection: ConnectionPoolItem { }
