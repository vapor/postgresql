import Foundation

/// Representable by a `T[]` column on the PostgreSQL database.
public protocol PostgreSQLArrayCustomConvertible: PostgreSQLDataCustomConvertible, Codable {
    /// The associated array element type
    associatedtype PostgreSQLArrayElement // :PostgreSQLDataCustomConvertible

    /// Convert an array of elements to self.
    static func convertFromPostgreSQLArray(_ data: [PostgreSQLArrayElement]) -> Self

    /// Convert self to an array of elements.
    func convertToPostgreSQLArray() -> [PostgreSQLArrayElement]
}

extension PostgreSQLArrayCustomConvertible {
    /// See `PostgreSQLDataCustomConvertible.convertFromPostgreSQLData(_:)`
    public static func convertFromPostgreSQLData(_ data: PostgreSQLData) throws -> Self {
        guard var value = data.data else {
            throw PostgreSQLError(identifier: "nullArray", reason: "Unable to decode PostgreSQL array from `null` data.")
        }


        /// Extract and convert each element.
        var array: [PostgreSQLArrayElement] = []

        let hasData = value.extract(Int32.self).bigEndian
        if hasData == 1 {
            /// grab the array metadata from the beginning of the data
            let metadata = value.extract(PostgreSQLArrayMetadata.self)
            guard let type = PostgreSQLArrayElement.self as? PostgreSQLDataCustomConvertible.Type else {
                /// FIXME: conditional conformance
                throw PostgreSQLError(
                    identifier: "arrayElement",
                    reason: "`\(Self.self)` element `\(PostgreSQLArrayElement.self)` does not conform to `PostgreSQLDataCustomConvertible`"
                )
            }

            for _ in 0..<metadata.count {
                let count = Int(value.extract(Int32.self).bigEndian)
                let subValue = value.extract(count: count)
                let psqlData = PostgreSQLData(type: metadata.type, format: data.format, data: subValue)
                let element = try type.convertFromPostgreSQLData(psqlData)
                array.append(element as! PostgreSQLArrayElement)
            }
        } else {
            array = []
        }

        return convertFromPostgreSQLArray(array)
    }

    /// See `PostgreSQLDataCustomConvertible.convertToPostgreSQLData()`
    public func convertToPostgreSQLData() throws -> PostgreSQLData {
        let elements = try convertToPostgreSQLArray().map {
            try ($0 as! PostgreSQLDataCustomConvertible).convertToPostgreSQLData()
        }

        guard let type = PostgreSQLArrayElement.self as? PostgreSQLDataCustomConvertible.Type else {
            /// FIXME: conditional conformance
            fatalError("PostgreSQLArrayCustomConvertible element type `\(PostgreSQLArrayElement.self)` does not conform to `PostgreSQLDataCustomConvertible`")
        }

        var data = Data()
        data += Int32(1).data // non-null
        data += Int32(0).data // b
        data += type.postgreSQLDataType.raw.data // type
        data += Int32(elements.count).data // length
        data += Int32(1).data // dimensions

        for element in elements {
            if let value = element.data {
                data += Int32(value.count).data
                data += value
            } else {
                data += Int32(0).data
            }
        }


        return PostgreSQLData(type: type.postgreSQLDataArrayType, format: .binary, data: data)
    }
}

fileprivate struct PostgreSQLArrayMetadata {
    /// Unknown
    private let _b: Int32

    /// The big-endian array element type
    private let _type: Int32

    /// The big-endian length of the array
    private let _count: Int32

    /// The big-endian number of dimensions
    private let _dimensions: Int32

    /// Converts the raw array elemetn type to DataType
    var type: PostgreSQLDataType {
        return .init(raw: _type.bigEndian, sql: "UNKNOWN")
    }

    /// The length of the array
    var count: Int32 {
        return _count.bigEndian
    }

    /// The  number of dimensions
    var dimensions: Int32 {
        return _dimensions.bigEndian
    }
}

extension PostgreSQLArrayMetadata: CustomStringConvertible {
    /// See `CustomStringConvertible.description`
    var description: String {
        return "\(type)[\(count)]"
    }
}

extension Array: PostgreSQLArrayCustomConvertible {
    /// See `PostgreSQLArrayCustomConvertible.PostgreSQLArrayElement`
    public typealias PostgreSQLArrayElement = Element

    /// See `PostgreSQLDataCustomConvertible.postgreSQLDataType`
    public static var postgreSQLDataType: PostgreSQLDataType {
        guard let wrapped = Element.self as? PostgreSQLDataCustomConvertible.Type else {
            /// FIXME: conditional conformance
            fatalError("Array element type `\(Element.self)` does not conform to `PostgreSQLDataCustomConvertible`")
        }
        return wrapped.postgreSQLDataType
    }

    /// See `PostgreSQLDataCustomConvertible.postgreSQLDataArrayType`
    public static var postgreSQLDataArrayType: PostgreSQLDataType {
        guard let wrapped = Element.self as? PostgreSQLDataCustomConvertible.Type else {
            /// FIXME: conditional conformance
            fatalError("Array element type `\(Element.self)` does not conform to `PostgreSQLDataCustomConvertible`")
        }
        return wrapped.postgreSQLDataArrayType
    }

    /// See `PostgreSQLArrayCustomConvertible.convertFromPostgreSQLArray(_:)`
    public static func convertFromPostgreSQLArray(_ data: [Element]) -> Array<Element> {
        return data
    }

    /// See `PostgreSQLArrayCustomConvertible.convertToPostgreSQLArray(_:)`
    public func convertToPostgreSQLArray() -> [Element] {
        return self
    }
}