import XCTest
import MySalahCore

private final class StubState: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: (Int, Data)] = [:]
    func put(_ url: URL, status: Int, body: String) { lock.withLock { responses[url.absoluteString] = (status, Data(body.utf8)) } }
    func take(_ url: URL) -> (Int, Data)? { lock.withLock { responses.removeValue(forKey: url.absoluteString) } }
}
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let state = StubState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let (status, data) = Self.state.take(url), let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class ProviderTests: XCTestCase {
    private func client(path: String, status: Int = 200, body: String) -> EzanVaktiProvider {
        let base = URL(string: "https://fixture.invalid/\(UUID().uuidString)")!
        StubProtocol.state.put(base.appendingPathComponent(path), status: status, body: body)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        return EzanVaktiProvider(session: URLSession(configuration: config), baseURL: base)
    }
    func testLocationEndpointMapping() async throws {
        let country = client(path: "ulkeler", body: """
        [{"UlkeID":"26","UlkeAdi":"DANİMARKA","UlkeAdiEn":"DENMARK"}]
        """)
        let countries = try await country.countries()
        XCTAssertEqual(countries.first?.id, "26")
        let region = client(path: "sehirler/26", body: """
        [{"SehirID":"685","SehirAdi":"DANİMARKA","SehirAdiEn":"DENMARK"}]
        """)
        let regions = try await region.regions(countryID: "26")
        XCTAssertEqual(regions.first?.id, "685")
        let district = client(path: "ilceler/685", body: """
        [{"IlceID":"12618","IlceAdi":"KOPENHAG","IlceAdiEn":"KOPENHAGEN"}]
        """)
        let districts = try await district.districts(regionID: "685")
        XCTAssertEqual(districts.first?.displayName(language: .tr), "KOPENHAG")
        XCTAssertEqual(districts.first?.displayName(language: .en), "KOPENHAGEN")
    }
    func testHTTPFailureAndMalformedResponse() async {
        do { _ = try await client(path: "ulkeler", status: 503, body: "unavailable").countries(); XCTFail("Expected HTTP error") }
        catch { XCTAssertEqual(error as? DataError, .http(503)) }
        do { _ = try await client(path: "ulkeler", body: "<html>error</html>").countries(); XCTFail("Expected decoding error") }
        catch { XCTAssertTrue(error is DecodingError) }
    }
}
