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
import CryptoKit
import Foundation

public final class ReaderTrustStoreUpdater: Sendable {

  private let pemUrl: URL
  private let session: URLSession
  private let cacheURLOverride: URL?

  private static let readTimeout: TimeInterval = 15

  /// - Parameters:
  ///   - pemUrl: endpoint returning a PEM bundle (one or more `CERTIFICATE` blocks)
  ///   - session: URLSession used for the fetch — defaults to a transient ephemeral session
  ///   - cacheURL: override for the on-disk cache path (test seam); defaults to `Self.cacheURL()`
  public init(
    pemUrl: URL,
    session: URLSession = URLSession(configuration: .ephemeral),
    cacheURL: URL? = nil
  ) {
    self.pemUrl = pemUrl
    self.session = session
    self.cacheURLOverride = cacheURL
  }

  /// Fetch the RP certificate bundle, write it to the on-disk cache, and return
  /// the parsed DER list. On network failure, fall back to the cached PEM from a
  /// previous run. On both failures, return an empty array — the caller keeps
  /// whatever certs it already trusted.
  public func fetchCertificates() async -> [Data] {
    let cacheURL: URL? = cacheURLOverride ?? (try? Self.cacheURL())
    if let pem = try? await downloadPem(), !pem.isEmpty {
      if let cacheURL {
        try? pem.write(to: cacheURL, atomically: true, encoding: .utf8)
      }
      return Self.parsePem(pem)
    }
    if let cacheURL, let cached = try? String(contentsOf: cacheURL, encoding: .utf8) {
      return Self.parsePem(cached)
    }
    return []
  }

  private func downloadPem() async throws -> String {
    var req = URLRequest(url: pemUrl)
    req.timeoutInterval = Self.readTimeout
    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      return ""
    }
    return String(data: data, encoding: .utf8) ?? ""
  }

  /// Parse a PEM bundle (possibly containing multiple `BEGIN CERTIFICATE` blocks)
  /// into an array of DER-encoded certificate bytes.
  public static func parsePem(_ pem: String) -> [Data] {
    let blocks = pem.components(separatedBy: "-----END CERTIFICATE-----")
    return blocks.compactMap { block -> Data? in
      guard let start = block.range(of: "-----BEGIN CERTIFICATE-----") else { return nil }
      let body = block[start.upperBound...]
        .components(separatedBy: .whitespacesAndNewlines)
        .joined()
      return Data(base64Encoded: body)
    }
  }

  /// Deduplicate by SHA-256 fingerprint of the DER bytes. Matches the Android
  /// `ReaderTrustStoreUpdater.deduplicateByFingerprint` definition — the same
  /// cert bundled locally and fetched from the URL collapses to one entry.
  public static func deduplicateByFingerprint(_ certs: [Data]) -> [Data] {
    var seen = Set<Data>()
    return certs.filter { cert in
      let fingerprint = Data(SHA256.hash(data: cert))
      return seen.insert(fingerprint).inserted
    }
  }

  /// On-disk cache location. iOS analogue of Android's `filesDir/rp-certificates-cache.pem`.
  /// `.applicationSupportDirectory` is private to the app, preserved across launches, and
  /// not OS-evictable like `.cachesDirectory`.
  public static func cacheURL() throws -> URL {
    let dir = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return dir.appendingPathComponent("rp-certificates-cache.pem")
  }
}
