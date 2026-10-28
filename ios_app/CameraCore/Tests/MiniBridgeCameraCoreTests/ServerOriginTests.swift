import Foundation
import XCTest
@testable import MiniBridgeCameraCore

final class ServerOriginTests: XCTestCase {
    func testCanonicalOriginAndExactHostPort() throws {
        let origin = try ServerOrigin(" https://NAS.Example:18443/ ")
        XCTAssertEqual(origin.address, "https://nas.example:18443")
        XCTAssertTrue(origin.allows(URL(string: "https://nas.example:18443/api/recordings?name=a")!))
        for raw in ["http://nas.example:18443/", "https://nas.example/", "https://nas.example.evil:18443/", "https://evil.example:18443/", "https://user@nas.example:18443/"] {
            XCTAssertFalse(origin.allows(URL(string: raw)!), raw)
        }
    }

    func testRejectSecretsParametersPathsAndInsecureSchemes() {
        for raw in ["", "nas.example", "http://nas.example", "file:///etc/passwd", "javascript:alert(1)", "https://user:password@nas.example", "https://nas.example/?token=secret", "https://nas.example/#secret", "https://nas.example/api", "https://nas.example:0", "https://nas.example:65536"] {
            XCTAssertThrowsError(try ServerOrigin(raw), raw)
        }
    }

    func testDefaultPortAndOriginBoundBlobDownloads() throws {
        let origin = try ServerOrigin("https://nas.example:443/")
        XCTAssertEqual(origin.address, "https://nas.example")
        XCTAssertTrue(origin.allowsResource(URL(string: "blob:https://nas.example/id")!))
        XCTAssertFalse(origin.allowsResource(URL(string: "blob:https://evil.example/id")!))
        XCTAssertFalse(origin.allowsResource(URL(string: "blob:null/id")!))
        XCTAssertFalse(origin.allowsResource(URL(string: "data:text/html,secret")!))
        XCTAssertFalse(origin.allowsResource(URL(string: "file:///tmp/video.zip")!))
    }

    func testDownloadFilenameCannotEscapeOwnedDirectory() {
        for raw in ["../../video.zip", "..\\..\\audio.wav", "\u{0}file:one\n.zip", "../", "..."] {
            let result = CameraDownloadPolicy.filename(raw)
            XCTAssertFalse(result.contains("/"))
            XCTAssertFalse(result.contains("\\"))
            XCTAssertFalse(result.contains(":"))
            XCTAssertFalse(result.hasPrefix("."))
            XCTAssertFalse(result.isEmpty)
        }
        XCTAssertEqual(CameraDownloadPolicy.filename("recording.wav"), "recording.wav")
        XCTAssertLessThanOrEqual(CameraDownloadPolicy.filename(String(repeating: "a", count: 500)).count, 120)
    }
}
