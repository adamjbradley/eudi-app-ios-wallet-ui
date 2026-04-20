/*
 * Copyright (c) 2025 European Commission
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * You may obtain a copy of the Licence at:
 * https://joinup.ec.europa.eu/software/page/eupl
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the Licence is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the Licence for the specific language
 * governing permissions and limitations under the Licence.
 */
import XCTest
@testable import logic_core

final class ReaderTrustStoreUpdaterTests: XCTestCase {

  static let pemBlockA = """
    -----BEGIN CERTIFICATE-----
    MIIBnzCCAUagAwIBAgIUQSg5NhDlxwDFyAM7YJe++0QGyKIwCgYIKoZIzj0EAwIw
    KTEnMCUGA1UEAwwedmVyaWZpZXIyLnRoZWF1c3RyYWxpYWhhY2suY29tMB4XDTI2
    MDIwMzAzNTIwM1oXDTI3MDIwMzAzNTIwM1owKTEnMCUGA1UEAwwedmVyaWZpZXIy
    LnRoZWF1c3RyYWxpYWhhY2suY29tMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE
    1Z2eGpdQVfWkAQQmNv8oT+lMwbhsFxWTZmhAYFHR5wa29fr30LbWoYQyrvOqOkSG
    rLaQ9PwoiedvGUtnN5Jd2qNMMEowKQYDVR0RBCIwIIIedmVyaWZpZXIyLnRoZWF1
    c3RyYWxpYWhhY2suY29tMB0GA1UdDgQWBBRt0uKz8aKVlUxKF9j6vhAsGl3nHDAK
    BggqhkjOPQQDAgNHADBEAiAQ+AlF3Q4dput8QTizDyKo99R/sv3CC7BzqEjOxxsn
    zQIgF+rnBf0HghobWkjSVNwP8j/ekasfjp+1HDJclcNaUvs=
    -----END CERTIFICATE-----
    """

  static let pemBlockB = """
    -----BEGIN CERTIFICATE-----
    MIIBkzCCATqgAwIBAgIUFO2gZtA0OguCDhsJ/o1d64wPcWAwCgYIKoZIzj0EAwIw
    KDEmMCQGA1UEAwwdcnAudGhlYXVzdHJhbGlhaGFjay5jb20gUlAgQ0EwHhcNMjYw
    NDE3MDc1NzAxWhcNMjcwNDE3MDc1NzAxWjAoMSYwJAYDVQQDDB1ycC50aGVhdXN0
    cmFsaWFoYWNrLmNvbSBSUCBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABAtG
    NbR+9219/Ej/K7rfdEwl1sxdlVWJhMd5Hps3ml+KfBnaMF3t/kcLrOfJFGDm7mQc
    91NgcpLp0CNKAbnjYvujQjBAMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQD
    AgEGMB0GA1UdDgQWBBRwBkmZZjR3i0qRWN7Ii0vEFwV6OjAKBggqhkjOPQQDAgNH
    ADBEAiBeMJ3E+uQBkOY6BQ/D1h1vGRoIznr25Vwy+31jcWA27wIgV4PrQ9J7UEXc
    fhpKRBn3CaN+z3oStgcE6PpIyAGdXWU=
    -----END CERTIFICATE-----
    """

  func testParsePemWithTwoBlocksReturnsTwoDerChunks() {
    let bundle = Self.pemBlockA + "\n" + Self.pemBlockB
    let ders = ReaderTrustStoreUpdater.parsePem(bundle)
    XCTAssertEqual(ders.count, 2)
    XCTAssertGreaterThan(ders[0].count, 50)
    XCTAssertGreaterThan(ders[1].count, 50)
    XCTAssertNotEqual(ders[0], ders[1])
  }

  func testParsePemRejectsNonCertText() {
    XCTAssertEqual(ReaderTrustStoreUpdater.parsePem(""), [])
    XCTAssertEqual(ReaderTrustStoreUpdater.parsePem("not a cert"), [])
    XCTAssertEqual(
      ReaderTrustStoreUpdater.parsePem("-----BEGIN WRONG-----\nAAAA\n-----END WRONG-----"),
      []
    )
  }

  func testDeduplicateKeepsUniqueDropsDuplicates() {
    let a = ReaderTrustStoreUpdater.parsePem(Self.pemBlockA).first!
    let b = ReaderTrustStoreUpdater.parsePem(Self.pemBlockB).first!
    let input = [a, b, a, b, a]
    let deduped = ReaderTrustStoreUpdater.deduplicateByFingerprint(input)
    XCTAssertEqual(deduped.count, 2)
    XCTAssertTrue(deduped.contains(a))
    XCTAssertTrue(deduped.contains(b))
  }

  func testCacheURLIsUnderApplicationSupport() throws {
    let url = try ReaderTrustStoreUpdater.cacheURL()
    let path = url.path
    XCTAssertTrue(path.contains("Application Support"), "got \(path)")
    XCTAssertTrue(path.hasSuffix("rp-certificates-cache.pem"))
  }
}
