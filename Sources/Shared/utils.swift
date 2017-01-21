// The MIT License (MIT)
// Copyright (c) 2017 Erik Little

// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
// documentation files (the "Software"), to deal in the Software without restriction, including without
// limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
// Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
// Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
// BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.

import Foundation
import SocksCore

public enum SwiftBotError : Error {
    case invalidMessage
}

public func encodeDataPacket(_ json: [String: Any]) -> [UInt8] {
    var packetData: [UInt8]!
    let objectData = encodeJSON(json)!.data(using: .utf8)!

    objectData.withUnsafeBytes {(bytes: UnsafePointer<UInt8>) in
        let buf = UnsafeMutableRawBufferPointer.allocate(count: 8)
        let data = Array(UnsafeBufferPointer(start: bytes, count: objectData.count))

        buf.storeBytes(of: UInt64(data.count).bigEndian, as: UInt64.self)

        packetData = Array(buf) + data
    }

    return packetData
}

public func encodeJSON(_ object: Any) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }

    return String(data: data, encoding: .utf8)
}

public func decodeJSON(_ string: String) -> Any? {
    guard let data = string.data(using: .utf8, allowLossyConversion: false) else { return nil }
    guard let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) else { return nil }

    return json
}

public func getDataFromSocket(_ socket: TCPInternetSocket) throws -> [UInt8] {
    let lengthOfMessageBytes = try socket.recv(maxBytes: 8).map(Int.init)

    guard lengthOfMessageBytes.count == 8 else { throw SwiftBotError.invalidMessage }

    let lengthOfMessage = lengthOfMessageBytes[0] << 56
                          | lengthOfMessageBytes[1] << 48
                          | lengthOfMessageBytes[2] << 40
                          | lengthOfMessageBytes[3] << 32
                          | lengthOfMessageBytes[4] << 24
                          | lengthOfMessageBytes[5] << 16
                          | lengthOfMessageBytes[6] << 8
                          | lengthOfMessageBytes[7]


    return try socket.recv(maxBytes: lengthOfMessage)
}
