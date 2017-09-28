import Dispatch
import TCP
import XCTest

class SocketsTests: XCTestCase {
    func testConnect() throws {
        let socket = try Socket()
        try socket.connect(hostname: "google.com")

        let data = """
        GET / HTTP/1.1\r
        Host: google.com\r
        Content-Length: 2\r
        \r
        hi
        """.data(using: .utf8)!

        let queue = DispatchQueue(label: "codes.vapor.test")

        let write = DispatchSource.makeWriteSource(fileDescriptor: socket.descriptor.raw, queue: queue)
        write.setEventHandler {
            _ = try! socket.write(data)
        }
        write.resume()

        let semaphore = DispatchSemaphore(value: 0)

        let read = DispatchSource.makeReadSource(fileDescriptor: socket.descriptor.raw, queue: queue)
        read.setEventHandler {
            let response = try! socket.read(max: 8_192)

            let string = String(data: response, encoding: .utf8)
            XCTAssert(string?.contains("HTTP/1.0 400 Bad Request") == true)
            semaphore.signal()
        }
        read.resume()

        XCTAssertNotNil([read, write])
        semaphore.wait()
    }

    func testBind() throws {
        let server = try Socket()
        try server.bind(hostname: "localhost", port: 8337)
        try server.listen()

        let queue = DispatchQueue(label: "codes.vapor.test")
        let semaphore = DispatchSemaphore(value: 0)

        var accepted: (Socket, DispatchSourceRead)?

        let read = DispatchSource.makeReadSource(fileDescriptor: server.descriptor.raw, queue: queue)
        read.setEventHandler {
            let client = try! server.accept()
            let read = DispatchSource.makeReadSource(
                fileDescriptor: client.descriptor.raw,
                queue: queue
            )
            read.setEventHandler {
                let data = try! client.read(max: 8_192)
                XCTAssertEqual(String(data: data, encoding: .utf8), "hello")
                semaphore.signal()
            }
            read.resume()
            
            accepted = (client, read)
            XCTAssertNotNil(accepted)
            XCTAssert(client.address?.remoteAddress == "127.0.0.1" || client.address?.remoteAddress == "0.0.0.0" || client.address?.remoteAddress == "::1")
        }
        read.resume()
        XCTAssertNotNil(read)

        try clientHello(port: 8337)

        semaphore.wait()
    }
    
    func testServer() throws {
        let server = try Server()
        try server.start(port: 8338)
        let semaphore = DispatchSemaphore(value: 0)
        
        server.drain { client in
            client.drain { buffer in
                XCTAssertEqual(String(bytes: buffer, encoding: .utf8), "hello")
                semaphore.signal()
            }
            
            client.start()
        }
        
        try clientHello(port: 8338)
        semaphore.wait()
    }

    static let allTests = [
        ("testConnect", testConnect),
        ("testBind", testBind),
        ("testServer", testServer),
    ]
}

fileprivate func clientHello(port: UInt16) throws {
    do {
        let client = try Socket(isNonBlocking: false)
        try client.connect(hostname: "localhost", port: port)
        let data = "hello".data(using: .utf8)!
        _ = try! client.write(data)
    }
}
