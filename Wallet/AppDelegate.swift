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

/// Swift-log LogHandler that routes every log line through NSLog so the output
/// isn't redacted as `<private>` on TestFlight / release builds. Temporary
/// diagnostic — visible via `idevicesyslog -u <udid>`.
struct NSLogLogHandler: LogHandler {
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
    NSLog("[EUDI-\(level)] [%@] %@ %@", label, "\(message)", meta)
  }
}

class AppDelegate: UIResponder, UIApplicationDelegate {

  private lazy var analyticsController: AnalyticsController = DIGraph.shared.resolver.force(AnalyticsController.self)
  private lazy var revocationWorkManager: RevocationWorkManager = DIGraph.shared.resolver.force(RevocationWorkManager.self)

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {

    // Route swift-log (EudiWalletKit, OpenID4VP lib, etc.) through NSLog so
    // warnings/errors show up un-redacted in iOS syslog. Diagnostic — safe to
    // revert once the DCQL matching bug is traced.
    LoggingSystem.bootstrap { label in
      var h: LogHandler = NSLogLogHandler(label: label)
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
