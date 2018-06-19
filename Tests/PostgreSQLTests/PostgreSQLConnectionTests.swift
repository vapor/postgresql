import PostgreSQL
import SQLBenchmark
import XCTest

class PostgreSQLConnectionTests: XCTestCase {
    struct VersionMetadata: Codable {
        var version: String
    }
    
    func testBenchmark() throws {
        let conn = try PostgreSQLConnection.makeTest(transport: .cleartext)
        let benchmarker = SQLBenchmarker(on: conn)
        try benchmarker.run()
    }
    
    func testVersion() throws {
        let client = try PostgreSQLConnection.makeTest(transport: .cleartext)
        let results = try client.select().column(.function("version", [])).all(decoding: VersionMetadata.self).wait()
        XCTAssertTrue(results[0].version.contains("10."))
    }

    func testUnverifiedSSLConnection() throws {
        let client = try PostgreSQLConnection.makeTest(transport: .unverifiedTLS)
        let results = try client.select().column(.function("version", [])).all(decoding: VersionMetadata.self).wait()
        XCTAssertTrue(results[0].version.contains("10."))
    }

    func testSelectTypes() throws {
        // 1247.typisdefined: 0x01 (BOOLEAN)
        // 1247.typbasetype: 0x00000000 (OID)
        // 1247.typnotnull: 0x00 (BOOLEAN)
        // 1247.typcategory: 0x42 (CHAR)
        // 1247.typname: 0x626f6f6c (NAME)
        // 1247.typbyval: 0x01 (BOOLEAN)
        // 1247.typrelid: 0x00000000 (OID)
        // 1247.typalign: 0x63 (CHAR)
        // 1247.typndims: 0x00000000 (INTEGER)
        // 1247.typacl: null
        // 1247.typsend: 0x00000985 (REGPROC)
        // 1247.typmodout: 0x00000000 (REGPROC)
        // 1247.typstorage: 0x70 (CHAR)
        // 1247.typispreferred: 0x01 (BOOLEAN)
        // 1247.typinput: 0x000004da (REGPROC)
        // 1247.typoutput: 0x000004db (REGPROC)
        // 1247.typlen: 0x0001 (SMALLINT)
        // 1247.typcollation: 0x00000000 (OID)
        // 1247.typdefaultbin: null
        // 1247.typelem: 0x00000000 (OID)
        // 1247.typnamespace: 0x0000000b (OID)
        // 1247.typtype: 0x62 (CHAR)
        // 1247.typowner: 0x0000000a (OID)
        // 1247.typdefault: null
        // 1247.typtypmod: 0xffffffff (INTEGER)
        // 1247.typarray: 0x000003e8 (OID)
        // 1247.typreceive: 0x00000984 (REGPROC)
        // 1247.typmodin: 0x00000000 (REGPROC)
        // 1247.typanalyze: 0x00000000 (REGPROC)
        // 1247.typdelim: 0x2c (CHAR)
        struct PGType: PostgreSQLTable {
            static let sqlTableIdentifierString = "pg_type"
            var typname: String
            var typnamespace: UInt32
            var typowner: UInt32
            var typlen: Int16
            var typbyval: Bool
            var typtype: Char
            var typcategory: Char
            var typispreferred: Bool
            var typisdefined: Bool
            var typdelim: Char
            var typrelid: UInt32
            var typelem: UInt32
            var typarray: UInt32
            var typinput: Regproc
            var typoutput: Regproc
            var typreceive: Regproc
            var typsend: Regproc
            var typmodin: Regproc
            var typmodout: Regproc
            var typanalyze: Regproc
            var typalign: Char
            var typstorage: Char
            var typnotnull: Bool
            var typbasetype: UInt32
            var typtypmod: Int
            var typndims: Int
            var typcollation: UInt32
//            var typdefaultbin: String?
//            var typdefault: String?
//            var typacl: String?
        }
        let client = try PostgreSQLConnection.makeTest(transport: .cleartext)
        let results = try client.select().all().from(PGType.self).all(decoding: PGType.self).wait()
        XCTAssert(results.count >= 350, "Results count not large enough: \(results.count)")
    }
    
    struct Foo: PostgreSQLTable {
        static let postgreSQLTable = "foo"
        var id: Int?
        var dict: Hello
    }
    
    struct Hello: Codable, ReflectionDecodable, Equatable {
        var message: String
    }

    func testStruct() throws {
        let client = try PostgreSQLConnection.makeTest(transport: .cleartext)
        
        struct Foo: PostgreSQLTable {
            var id: Int?
            var dict: Hello
        }

        defer {
            _ = try? client.drop(table: Foo.self).ifExists().run().wait()
        }
        try client.create(table: Foo.self)
            .column(for: \Foo.id, .primaryKey)
            .column(for: \Foo.dict)
            .run().wait()

        let hello = Hello(message: "Hello, world!")
        try client.insert(into: Foo.self).value(Foo(id: nil, dict: hello)).run().wait()

        let fetch = try client.select().all().from(Foo.self).all(decoding: Foo.self).wait()
        switch fetch.count {
        case 1:
            XCTAssertEqual(fetch[0].id, 1)
            XCTAssertEqual(fetch[0].dict.message, "Hello, world!")
        default: XCTFail("invalid row count")
        }
    }

    func testNull() throws {
        let conn = try PostgreSQLConnection.makeTest(transport: .cleartext)

        struct Nulltest: PostgreSQLTable {
            var i: Int?
            var d: Date?
        }
        
        defer {
            try? conn.drop(table: Nulltest.self).ifExists().run().wait()
        }
        try conn.create(table: Nulltest.self)
            .column(for: \Nulltest.i, .primaryKey)
            .column(for: \Nulltest.d)
            .run().wait()
        
        try conn.insert(into: Nulltest.self).value(Nulltest(i: nil, d: nil)).run().wait()
    }

    func testGH24() throws {
        /// PREPARE
        let client = try PostgreSQLConnection.makeTest(transport: .cleartext)

        /// CREATE
        let _ = try client.query("""
        CREATE TABLE "users" ("id" UUID PRIMARY KEY, "name" TEXT NOT NULL, "username" TEXT NOT NULL)
        """).wait()
        defer { _ = try! client.simpleQuery("DROP TABLE users").wait() }
        let _ = try client.query("""
        CREATE TABLE "acronyms" ("id" BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, "short" TEXT NOT NULL, "long" TEXT NOT NULL, "userID" UUID NOT NULL, FOREIGN KEY ("userID") REFERENCES "users" ("id"), FOREIGN KEY ("userID") REFERENCES "users" ("id"))
        """).wait()
        defer { _ = try! client.simpleQuery("DROP TABLE acronyms").wait() }
        let _ = try client.query("""
        CREATE TABLE "categories" ("id" BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, "name" TEXT NOT NULL)
        """).wait()
        defer { _ = try! client.simpleQuery("DROP TABLE categories").wait() }
        let _ = try client.query("""
        CREATE TABLE "acronym+category" ("id" UUID PRIMARY KEY, "acronymID" BIGINT NOT NULL, "categoryID" BIGINT NOT NULL, FOREIGN KEY ("acronymID") REFERENCES "acronyms" ("id"), FOREIGN KEY ("categoryID") REFERENCES "categories" ("id"), FOREIGN KEY ("acronymID") REFERENCES "acronyms" ("id"), FOREIGN KEY ("categoryID") REFERENCES "categories" ("id"))
        """).wait()
        defer { _ = try! client.simpleQuery("DROP TABLE \"acronym+category\"").wait() }

        /// INSERT
        let userUUID = UUID()
        let _ = try client.query(
            """
            INSERT INTO "users" ("id", "name", "username") VALUES ($1, $2, $3)
            """,
            [userUUID, "Vapor Test", "vapor" ]
        ).wait()
        let _ = try client.query(
            """
            INSERT INTO "acronyms" ("id", "userID", "short", "long") VALUES ($1, $2, $3, $4)
            """,
            [1, userUUID, "ilv", "i love vapor"]
        ).wait()
        let _ = try client.query(
            """
            INSERT INTO "categories" ("id", "name") VALUES ($1, $2);
            """,
            [1, "all"]
        ).wait()


        /// SELECT
        let acronyms = client.query(
            """
            SELECT "acronyms".* FROM "acronyms" WHERE ("acronyms"."id" = $1) LIMIT 1 OFFSET 0
            """,
            [1]
        )
        let categories = client.query(
            """
            SELECT "categories".* FROM "categories" WHERE ("categories"."id" = $1) LIMIT 1 OFFSET 0
            """,
            [1]
        )

        _ = try acronyms.wait()
        _ = try categories.wait()
    }

    func testURLParsing() throws {
        let databaseURL = "postgres://username:password@localhost:5432/database"
        let config = try PostgreSQLDatabaseConfig(url: databaseURL)!
        XCTAssertEqual("\(config.serverAddress)", "ServerAddress(storage: PostgreSQL.PostgreSQLConnection.ServerAddress.Storage.tcp(hostname: \"localhost\", port: 5432))")
        XCTAssertEqual(config.username, "username")
        XCTAssertEqual(config.password, "password")
        XCTAssertEqual(config.database, "database")
    }

    struct Overview: Codable {
        var platform: String
        var identifier: String
        var count: Int
    }

    // https://github.com/vapor/postgresql/issues/46
    func testGH46() throws {
        let conn = try PostgreSQLConnection.makeTest(transport: .cleartext)
        _ = try conn.simpleQuery("CREATE TABLE apps (id INT, platform TEXT, identifier TEXT)").wait()
        defer { _ = try? conn.simpleQuery("DROP TABLE apps").wait() }
        _ = try conn.simpleQuery("INSERT INTO apps VALUES (1, 'a', 'b')").wait()
        _ = try conn.simpleQuery("INSERT INTO apps VALUES (2, 'c', 'd')").wait()
        _ = try conn.simpleQuery("INSERT INTO apps VALUES (3, 'a', 'd')").wait()
        _ = try conn.simpleQuery("INSERT INTO apps VALUES (4, 'a', 'b')").wait()
        let overviews = try conn.raw("SELECT platform, identifier, COUNT(id) as count FROM apps GROUP BY platform, identifier").all(decoding: Overview.self).wait()
        XCTAssertEqual(overviews.count, 3)
    }

    func testDataDecoder() throws {
        enum Toy: String, Codable {
            case bologna, plasticBag
        }

        let toy = try PostgreSQLDataDecoder().decode(Toy.self, from: PostgreSQLData(.text, text: "bologna"))
        print(toy)

        struct Pet: Codable {
            var name: String
            var toys: [Toy]
        }

        let pet = try! PostgreSQLDataDecoder().decode(Pet.self, from: PostgreSQLData(.jsonb, binary: [0x01] + JSONEncoder().encode(Pet(name: "Zizek", toys: [.bologna, .plasticBag]))))
        print(pet)
    }

    func testRowDecoder() throws {
        enum Toy: String, Codable {
            case bologna, plasticBag
        }

        struct Pet: Codable {
            var name: String
            var toys: [Toy]
        }

        struct User: Codable {
            var id: UUID?
            var name: String
            var pet: Pet
            var toy: Toy?
        }

        let row: [PostgreSQLColumn: PostgreSQLData] = try [
            PostgreSQLColumn(tableOID: 5, name: "id"): PostgreSQLData(.uuid, binary: Data([0x54, 0xd6, 0xfc, 0x55, 0x82, 0x9b, 0x48, 0x29, 0x87, 0xc9, 0x50, 0xe4, 0xd4, 0xd9, 0x5c, 0x3b])),
            PostgreSQLColumn(tableOID: 5, name: "name"): PostgreSQLData(.text, binary: Data("tanner".utf8)),
            PostgreSQLColumn(tableOID: 5, name: "pet"): PostgreSQLData(.jsonb, binary: [0x01] + JSONEncoder().encode(Pet(name: "Zizek", toys: [.bologna, .plasticBag]))),
            PostgreSQLColumn(tableOID: 5, name: "toy"): PostgreSQLData(.text, text: "bologna"),
        ]
        let user = try! PostgreSQLRowDecoder().decode(User.self, from: row, tableOID: 5)
        print(user)
    }

    func testRowCodableNested() throws {
        enum Toy: String, Codable {
            case bologna, plasticBag
        }

        enum UserType: String, Codable {
            case admin
        }

        struct Pet: Codable {
            var name: String
            var toys: [Toy]
        }

        struct User: Codable {
            var id: UUID?
            var name: String
            var type: UserType
            var pet: Pet
        }

        let userA = User(id: UUID(), name: "Tanner", type: .admin, pet: .init(name: "Zizek", toys: [.bologna]))
        let row = try PostgreSQLDataEncoder().encode(userA)
        print(row)
    }

    func testRowCodableTypes() throws {
        let conn = try PostgreSQLConnection.makeTest(transport: .cleartext)
        
        struct Types: PostgreSQLTable, Codable {
            static let postgreSQLTable = "types"
            var id: Int?
            var bool: Bool
            var string: String
            var int: Int
            var int8: Int8
            var int16: Int16
            var int32: Int32
            var int64: Int64
            var uint: UInt
            var uint8: UInt8
            var uint16: UInt16
            var uint32: UInt32
            var uint64: UInt64
            var double: Double
            var float: Float
            var date: Date
            var decimal: Decimal
        }

        defer {
            try? conn.drop(table: Types.self).ifExists().run().wait()
        }
        try conn.create(table: Types.self)
            .column(for: \Types.id)
            .column(for: \Types.bool)
            .column(for: \Types.string)
            .column(for: \Types.int)
            .column(for: \Types.int8)
            .column(for: \Types.int16)
            .column(for: \Types.int32)
            .column(for: \Types.int64)
            .column(for: \Types.uint)
            .column(for: \Types.uint8)
            .column(for: \Types.uint16)
            .column(for: \Types.uint32)
            .column(for: \Types.uint64)
            .column(for: \Types.double)
            .column(for: \Types.float)
            .column(for: \Types.date)
            .column(for: \Types.decimal)
            .run().wait()
        
        let typesA = Types(id: nil, bool: true, string: "hello", int: 1, int8: 2, int16: 3, int32: 4, int64: 5, uint: 6, uint8: 7, uint16: 8, uint32: 9, uint64: 10, double: 13.37, float: 3.14, date: Date(), decimal: .init(-1.234))
        try conn.insert(into: Types.self).value(typesA).run().wait()
        let rows = try conn.select().all().from(Types.self).all(decoding: Types.self).wait()
        switch rows.count {
        case 1:
            let typesB = rows[0]
            XCTAssertEqual(typesA.bool, typesB.bool)
            XCTAssertEqual(typesA.string, typesB.string)
            XCTAssertEqual(typesA.int, typesB.int)
            XCTAssertEqual(typesA.int8, typesB.int8)
            XCTAssertEqual(typesA.int16, typesB.int16)
            XCTAssertEqual(typesA.int32, typesB.int32)
            XCTAssertEqual(typesA.int64, typesB.int64)
            XCTAssertEqual(typesA.uint, typesB.uint)
            XCTAssertEqual(typesA.uint8, typesB.uint8)
            XCTAssertEqual(typesA.uint16, typesB.uint16)
            XCTAssertEqual(typesA.uint32, typesB.uint32)
            XCTAssertEqual(typesA.uint64, typesB.uint64)
            XCTAssertEqual(typesA.double, typesB.double)
            XCTAssertEqual(typesA.float, typesB.float)
            XCTAssertEqual(typesA.date, typesB.date)
            XCTAssertEqual(typesA.decimal, typesB.decimal)
        default: XCTFail("Invalid row count")
        }
    }

    // https://github.com/vapor/postgresql/issues/63
    func testTimeTz() throws {
        struct Time: PostgreSQLTable, Equatable {
            static let sqlTableIdentifierString = "timetest"
            var timestamptz: Date
        }
        
        let conn = try PostgreSQLConnection.makeTest(transport: .cleartext)
        defer {
            try? conn.drop(table: Time.self).ifExists().run().wait()
        }
        try conn.create(table: Time.self).column(for: \Time.timestamptz).run().wait()

        let time = Time(timestamptz: .init())
        try conn.insert(into: Time.self).value(time).run().wait()
        let fetch: [Time] = try conn.select().all().from(Time.self).all(decoding: Time.self).wait()
        switch fetch.count {
        case 1:
            XCTAssertEqual(fetch[0], time)
        default: XCTFail("invalid row count")
        }
    }

    func testListen() throws {
        let conn = try PostgreSQLConnection.makeTest(transport: .cleartext)
        let done = conn.listen("foo") { message in
            XCTAssertEqual(message, "hi")
            return true
        }
        do {
            let conn = try PostgreSQLConnection.makeTest(transport: .cleartext)
            _ = try conn.notify("foo", message: "hi").wait()
        }
        try done.wait()
    }

    // https://github.com/vapor/postgresql/issues/56
    func testSum() throws {
        let conn = try PostgreSQLConnection.makeTest(transport: .cleartext)
        struct Sum: Decodable {
            var sum: Double
        }
        let rows: [Sum] = try conn.select().column(.function("SUM", [.expression(3.14)], as: .identifier("sum"))).all(decoding: Sum.self).wait()
        switch rows.count {
        case 1: XCTAssertEqual(rows[0].sum, 3.14)
        default: XCTFail("invalid row count")
        }
    }

    func testOrderBy() throws {
        struct Planet: PostgreSQLTable, Equatable {
            var id: Int?
            var name: String
            init(id: Int? = nil, name: String) {
                self.id = id
                self.name = name
            }
        }

        let conn = try PostgreSQLConnection.makeTest(transport: .cleartext)
        defer {
            try? conn.drop(table: Planet.self).ifExists().run().wait()
        }
        try conn.create(table: Planet.self)
            .column(for: \Planet.id)
            .column(for: \Planet.name)
            .run().wait()

        try conn.insert(into: Planet.self).value(Planet(name: "Venus"))
            //.returning(.all)
            .run().wait()
        // XCTAssertEqual(planet.id, 1)

        try conn.insert(into: Planet.self)
            .value(Planet(name: "Earth"))
            .value(Planet(name: "Pluto"))
            .value(Planet(name: "Saturn"))
            .value(Planet(name: "Neptune"))
            .run().wait()

        let planetsA = try conn.select().all().from(Planet.self)
            .all(decoding: Planet.self).wait()
        let planetsB = try conn.select().all().from(Planet.self)
            .orderBy(\Planet.name)
            .all(decoding: Planet.self).wait()
        XCTAssertNotEqual(planetsA, planetsB)
    }

    // https://github.com/vapor/postgresql/issues/53
    func testInvalidDate() throws {
        let conn = try PostgreSQLConnection.makeTest(transport: .cleartext)
        
        struct Time: PostgreSQLTable, Equatable {
            static let sqlTableIdentifierString = "timetest"
            var date: Date
        }
        
        defer { try? conn.drop(table: Time.self).ifExists().run().wait() }
        try conn.create(table: Time.self).column(for: \Time.date).run().wait()

        try conn.raw("INSERT INTO timetest (date) VALUES ('0214-02-05')").run().wait()
        let fetch: [Time] = try conn.select().all().from(Time.self).all(decoding: Time.self).wait()
        switch fetch.count {
        case 1: XCTAssertEqual(fetch[0].date.timeIntervalSince1970, -55410998400)
        default: XCTFail("invalid row count")
        }
    }
    
    // https://github.com/vapor/postgresql/issues/80
    func testEmptyArray() throws {
        do {
            var messages: [String] = []
            let a = try PostgreSQLDataEncoder().encode(messages)
            print(a)
            messages.append("hello")
            let b = try PostgreSQLDataEncoder().encode(messages)
            print(b)
            messages.append("world")
            let c = try PostgreSQLDataEncoder().encode(messages)
            print(c)
        }
        do {
            var messages: [Int] = []
            let a = try PostgreSQLDataEncoder().encode(messages)
            print(a)
            messages.append(42)
            let b = try PostgreSQLDataEncoder().encode(messages)
            print(b)
            messages.append(1337)
            let c = try PostgreSQLDataEncoder().encode(messages)
            print(c)
        }
    }

    static var allTests = [
        ("testBenchmark", testBenchmark),
        ("testVersion", testVersion),
        ("testUnverifiedSSLConnection", testUnverifiedSSLConnection),
        ("testSelectTypes", testSelectTypes),
        ("testStruct", testStruct),
        ("testNull", testNull),
        ("testGH24", testGH24),
        ("testURLParsing", testURLParsing),
        ("testGH46", testGH46),
        ("testDataDecoder", testDataDecoder),
        ("testRowDecoder", testRowDecoder),
        ("testRowCodableNested", testRowCodableNested),
        ("testRowCodableTypes", testRowCodableTypes),
        ("testTimeTz", testTimeTz),
        ("testListen", testListen),
        ("testSum", testSum),
        ("testOrderBy", testOrderBy),
        ("testInvalidDate", testInvalidDate),
        ("testEmptyArray", testEmptyArray),
    ]
}

extension PostgreSQLConnection {
    /// Creates a test event loop and psql client over ssl.
    static func makeTest(transport: PostgreSQLConnection.TransportConfig) throws -> PostgreSQLConnection {
        #if Xcode
        return try _makeTest(hostname: "localhost", port: transport.isTLS ? 5433 : 5432, password: "vapor_password", transport: transport)
        #else
        return try _makeTest(hostname: transport.isTLS ? "tls" : "cleartext", port: 5432, password: "vapor_password", transport: transport)
        #endif
    }

    /// Creates a test connection.
    private static func _makeTest(hostname: String, port: Int, password: String? = nil, transport: PostgreSQLConnection.TransportConfig = .cleartext) throws -> PostgreSQLConnection {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let client = try PostgreSQLConnection.connect(hostname: hostname, port: port, transport: transport, on: group) { error in
            XCTFail("\(error)")
        }.wait()
        _ = try client.authenticate(username: "vapor_username", database: "vapor_database", password: password).wait()
        client.logger = DatabaseLogger(database: .psql, handler: PrintLogHandler())
        return client
    }
}

func +=<T>(lhs: inout [T], rhs: T) {
    lhs.append(rhs)
}








extension ReflectionDecodable where Self: Decodable {
    public static func reflectDecoded() throws -> (Self, Self) {
        return try (Self.init(from: ArityDecoder(false)), Self.init(from: ArityDecoder(true)))
    }
}

private struct ArityDecoder: Decoder {
    let codingPath: [CodingKey] = []
    let userInfo: [CodingUserInfoKey: Any] = [:]
    let arity: Bool
    init(_ arity: Bool) {
        self.arity = arity
    }
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        return .init(ArityKeyedDecodingContainer(arity))
    }
    
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        fatalError()
    }
    
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        fatalError()
    }
    
    private struct ArityKeyedDecodingContainer<Key>: KeyedDecodingContainerProtocol where Key: CodingKey {
        let allKeys: [Key] = []
        
        let codingPath: [CodingKey] = []
        let userInfo: [CodingUserInfoKey: Any] = [:]
        let arity: Bool
        init(_ arity: Bool) {
            self.arity = arity
        }
        
        
        func contains(_ key: Key) -> Bool {
            return true
        }
        
        func decodeNil(forKey key: Key) throws -> Bool {
            return true
        }
        
        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
            return arity
        }
        
        func decode(_ type: String.Type, forKey key: Key) throws -> String {
            return arity ? "1" : "0"
        }
        
        func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
            return arity ? 1 : 0
        }
        
        func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
            return arity ? 1 : 0
        }
        
        func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
            return arity ? 1 : 0
        }
        
        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
            return arity ? 1 : 0
        }
        
        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
            return arity ? 1 : 0
        }
        
        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
            return arity ? 1 : 0
        }
        
        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
            return arity ? 1 : 0
        }
        
        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
            return arity ? 1 : 0
        }
        
        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
            return arity ? 1 : 0
        }
        
        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
            return arity ? 1 : 0
        }
        
        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
            return arity ? 1 : 0
        }
        
        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
            return arity ? 1 : 0
        }
        
        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
            return try T.init(from: ArityDecoder(arity))
        }
        
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            return .init(ArityKeyedDecodingContainer<NestedKey>(arity))
        }
        
        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            fatalError()
        }
        
        func superDecoder() throws -> Decoder {
            return ArityDecoder(arity)
        }
        
        func superDecoder(forKey key: Key) throws -> Decoder {
            return ArityDecoder(arity)
        }
    }
}
