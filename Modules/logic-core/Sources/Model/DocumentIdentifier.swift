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

public enum DocumentTypeIdentifier: RawRepresentable, Equatable, Sendable, Hashable {

  case mDocPid
  case sdJwtPid
  case other(formatType: String)

  public var rawValue: String {
    return switch self {
    case .mDocPid:
      Self.mDocPidDocType
    case .sdJwtPid:
      Self.sdJwtPidDocType
    case .other(let formatType):
      formatType
    }
  }

  public init(rawValue: String) {
    switch rawValue {
    case Self.mDocPidDocType:
      self = .mDocPid
    case Self.sdJwtPidDocType:
      self = .sdJwtPid
    default:
      self = .other(formatType: rawValue)
    }
  }

  /// `true` for the canonical EU PID (mDoc + SD-JWT VC) *and* for
  /// country-variant PID VCTs the wallet recognises as regional PIDs.
  /// Used by the onboarding "Add your first document" list so shoppers on
  /// an AU build see `urn:au:gov:mygovid:pid:1` alongside `urn:eudi:pid:1`,
  /// instead of only the generic EU PID.
  ///
  /// Other credential types (driving licences, Medicare, PAN, etc.) are
  /// intentionally excluded — they are "extra documents" that require a
  /// PID to be present before they can be added.
  public var isPidLike: Bool {
    switch self {
    case .mDocPid, .sdJwtPid:
      return true
    case .other(let formatType):
      return Self.countryPidVcts.contains(formatType)
    }
  }
}

private extension DocumentTypeIdentifier {
  static let mDocPidDocType = "eu.europa.ec.eudi.pid.1"
  static let sdJwtPidDocType = "urn:eudi:pid:1"

  /// Regional PID VCTs recognised by `isPidLike`. Keep in sync with the
  /// per-variant `trustedCredentialVcts` in `AppBuildVariant` (only the
  /// PID entries — driving licences and Medicare are not PIDs).
  static let countryPidVcts: Set<String> = [
    "urn:au:gov:mygovid:pid:1",
    "urn:in:gov:aadhaar:pid:1"
  ]
}
