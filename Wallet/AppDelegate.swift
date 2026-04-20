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
import Foundation
import UIKit
import logic_assembly
import logic_core
import Logging
import SDWebImageSVGCoder

/// LogHandler that fans every swift-log message to BOTH:
/// - NSLog (realtime, streamable via `idevicesyslog -u <udid> | grep EUDI-`)
/// - `Library/Caches/eudi-ios-wallet-logs` (persistent, retrieved via
///   Xcode → Devices → Download Container → AppData/Library/Caches/…)
///
/// Diagnostic. Release-safe: EudiWalletKit's own `initializeLogging()` is only
/// wired to file (stdout gated by `_isDebugAssertConfiguration()`), so we
/// claim the bootstrap first and add NSLog alongside a file writer that uses
/// the same path EudiWalletKit would have used.
struct DiagnosticLogHandler: LogHandler {
  private static let logURL: URL? = {
    guard let dir = try? FileManager.getCachesDirectory() else { return nil }
    return dir.appendingPathComponent("eudi-ios-wallet-logs")
  }()
  private static let fileHandle: FileHandle? = {
    guard let url = logURL else { return nil }
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    let fh = try? FileHandle(forWritingTo: url)
    fh?.seekToEndOfFile()
    return fh
  }()
  private static let fileQueue = DispatchQueue(label: "eudi.diag.filelog")
  // ISO8601DateFormatter isn't Sendable; access is serialized through fileQueue,
  // so `nonisolated(unsafe)` is a deliberate opt-out of the strict-concurrency check.
  nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  var metadata: Logger.Metadata = [:]
  var logLevel: Logger.Level = .trace
  let label: String

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?,
           source: String, file: String, function: String, line: UInt) {
    let meta = metadata.flatMap { $0.isEmpty ? nil : $0.map { "\($0.key)=\($0.value)" }.joined(separator: " ") } ?? ""
    let msg = "\(message)"
    NSLog("[EUDI-\(level)] [%@] %@ %@", label, msg, meta)
    let now = Date()
    let capturedLabel = label
    Self.fileQueue.async {
      let ts = Self.isoFormatter.string(from: now)
      let lineText = "\(ts) \(level) \(capturedLabel): \(msg)\(meta.isEmpty ? "" : " \(meta)")\n"
      if let data = lineText.data(using: .utf8) {
        Self.fileHandle?.write(data)
      }
    }
  }
}

class AppDelegate: UIResponder, UIApplicationDelegate {

  private lazy var analyticsController: AnalyticsController = DIGraph.shared.resolver.force(AnalyticsController.self)
  private lazy var revocationWorkManager: RevocationWorkManager = DIGraph.shared.resolver.force(RevocationWorkManager.self)

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {

    // Claim the swift-log bootstrap BEFORE any consumer (EudiWalletKit,
    // OpenID4VP) constructs a Logger. In release builds EudiWalletKit's own
    // bootstrap would only write to file; we want NSLog too for realtime
    // idevicesyslog streaming. Also see WalletKitController — that code must
    // NOT reassign walletKit.logFileName post-init, or EudiWalletKit's didSet
    // calls LoggingSystem.bootstrap a second time and hits preconditionFailure.
    LoggingSystem.bootstrap { label in
      var h: LogHandler = DiagnosticLogHandler(label: label)
      h.logLevel = .trace
      return h
    }

    // Initialize Reporting
    initializeReporting()

    // Initialize Revocation Worker
    initializeRevocationWorker()

    // Register the SVG coder so SDWebImage can decode & render .svg images
    registerSvgCoderToSdImage()

    return true
  }

  func application(
    _ application: UIApplication,
    shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier
  ) -> Bool {
    switch extensionPointIdentifier {
    case UIApplication.ExtensionPointIdentifier.keyboard: return false
    default: return true
    }
  }

  private func initializeReporting() {
    analyticsController.initialize()
  }

  private func registerSvgCoderToSdImage() {
    SDImageCodersManager.shared.addCoder(SDImageSVGCoder.shared)
  }

  private func initializeRevocationWorker() {
    Task { await revocationWorkManager.start() }
  }
}
