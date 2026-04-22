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
import logic_business
import EudiWalletKit

struct ReaderConfig: Sendable {
  public let trustedCerts: [Data]
}

protocol WalletKitConfig: Sendable {

  /**
   * VCI Configuration
   */
  var vciConfig: [String: OpenId4VciConfiguration] { get }

  /**
   * VP Configuration
   */
  var vpConfig: OpenId4VpConfiguration { get }

  /**
   * Reader Configuration
   */
  var readerConfig: ReaderConfig { get }

  /**
   * User authentication required accessing core's secure storage
   */
  var userAuthenticationRequired: Bool { get }

  /**
   * Service name for documents key chain storage
   */
  var documentStorageServiceName: String { get }

  /**
   * The name of the file to be created to store logs
   */
  var logFileName: String { get }

  /**
   * Document categories
   */
  var documentsCategories: DocumentCategories { get }

  /**
   * Logger For Transactions
   */
  var transactionLogger: TransactionLogger { get }

  /**
   * The interval (in seconds) at which revocations are checked.
   */
  var revocationInterval: TimeInterval { get }

  /**
   * Configuration for document issuance, including default rules and specific overrides.
   */
  var documentIssuanceConfig: DocumentIssuanceConfig { get }

  /**
   * URL of a PEM bundle listing trusted RP/verifier certificates. The wallet
   * fetches this at startup and merges the result with `readerConfig.trustedCerts`.
   * Return `nil` to disable dynamic fetching for a flavor.
   */
  var rpCertificatesUrl: URL? { get }
}

struct WalletKitConfigImpl: WalletKitConfig {

  let configLogic: ConfigLogic
  let transactionLoggerImpl: TransactionLogger
  let walletKitAttestationProvider: WalletKitAttestationProvider

  init(
    configLogic: ConfigLogic,
    transactionLogger: TransactionLogger,
    walletKitAttestationProvider: WalletKitAttestationProvider
  ) {
    self.configLogic = configLogic
    self.transactionLoggerImpl = transactionLogger
    self.walletKitAttestationProvider = walletKitAttestationProvider
  }

  var userAuthenticationRequired: Bool {
    false
  }

  var vciConfig: [String: OpenId4VciConfiguration] {

    let openId4VciConfigurations: [OpenId4VciConfiguration] = {
      switch configLogic.appBuildVariant {
      case .DEMO:
        return [
          .init(
            credentialIssuerURL: "https://issuer.eudiw.dev",
            clientId: "wallet-dev",
            keyAttestationsConfig: .init(walletAttestationsProvider: walletKitAttestationProvider),
            authFlowRedirectionURI: URL(string: "eu.europa.ec.euidi://authorization")!,
            usePAR: true,
            useDpopIfSupported: true,
            cacheIssuerMetadata: true
          ),
          .init(
            credentialIssuerURL: "https://issuer-backend.eudiw.dev",
            clientId: "wallet-dev",
            keyAttestationsConfig: .init(walletAttestationsProvider: walletKitAttestationProvider),
            authFlowRedirectionURI: URL(string: "eu.europa.ec.euidi://authorization")!,
            usePAR: true,
            useDpopIfSupported: true,
            cacheIssuerMetadata: true
          )
        ]
      case .AU:
        // Point at the AU tenant's scoped OID4VCI endpoint so wallet-initiated
        // /authorize works. walt.id's root /draft13/authorize is a shared
        // multi-tenant endpoint that requires issuer_state (only present in
        // offer-initiated flows). Per-tenant endpoints accept wallet-initiated
        // requests without issuer_state. EudiWalletKit's getBaseUrl() path
        // stripping only applies to offer-routing, not to the configured
        // issuer URL used for fetching metadata + driving /par + /authorize.
        return [
          .init(
            credentialIssuerURL: "https://issuer.theaustraliahack.com/issuers/4bb447ff-661f-4589-bf17-6d97d2a322be/draft13",
            clientId: "eudi-wallet-au",
            keyAttestationsConfig: .init(walletAttestationsProvider: walletKitAttestationProvider),
            authFlowRedirectionURI: URL(string: "eu.europa.ec.euidi://authorization")!,
            usePAR: true,
            useDpopIfSupported: true,
            cacheIssuerMetadata: true
          )
        ]
      case .IN:
        return [
          .init(
            credentialIssuerURL: "https://issuer.theaustraliahack.com/issuers/94da79a8-15d2-4060-a4db-69b01a8057d2/draft13",
            clientId: "eudi-wallet-in",
            keyAttestationsConfig: .init(walletAttestationsProvider: walletKitAttestationProvider),
            authFlowRedirectionURI: URL(string: "eu.europa.ec.euidi://authorization")!,
            usePAR: true,
            useDpopIfSupported: true,
            cacheIssuerMetadata: true
          )
        ]
      case .DEV:
        return [
          .init(
            credentialIssuerURL: "https://ec.dev.issuer.eudiw.dev",
            clientId: "wallet-dev",
            keyAttestationsConfig: .init(walletAttestationsProvider: walletKitAttestationProvider),
            authFlowRedirectionURI: URL(string: "eu.europa.ec.euidi://authorization")!,
            usePAR: true,
            useDpopIfSupported: true,
            cacheIssuerMetadata: true
          ),
          .init(
            credentialIssuerURL: "https://dev.issuer-backend.eudiw.dev",
            clientId: "wallet-dev",
            keyAttestationsConfig: .init(walletAttestationsProvider: walletKitAttestationProvider),
            authFlowRedirectionURI: URL(string: "eu.europa.ec.euidi://authorization")!,
            usePAR: true,
            useDpopIfSupported: true,
            cacheIssuerMetadata: true
          )
        ]
      }
    }()

    return openId4VciConfigurations.reduce(
      into: [String: OpenId4VciConfiguration]()
    ) { dict, config in
      guard
        let issuer = config.credentialIssuerURL,
        let url = URL(string: issuer),
        let host = url.host
      else {
        return
      }
      dict[host] = config
    }
  }

  var vpConfig: OpenId4VpConfiguration {
    .init(clientIdSchemes: [.x509SanDns, .x509Hash])
  }

  var readerConfig: ReaderConfig {
    let certificates = [
      "pidissuerca02_cz",
      "pidissuerca02_ee",
      "pidissuerca02_eu",
      "pidissuerca02_lu",
      "pidissuerca02_nl",
      "pidissuerca02_pt",
      "pidissuerca02_ut",
      "r45_staging",
      // Self-signed CAs for our dev RPs. Without these, iOS rejects the signed
      // authorization request (JAR) from verifier2 and the wallet surfaces a
      // misleading "requested document is not available" error. Android trusts
      // the same pair via R.raw.verifier2_theaustraliahack + rp_theaustraliahack.
      "verifier2_theaustraliahack",
      "rp_theaustraliahack"
    ]
    let certsData: [Data] = certificates.compactMap {
      Data(name: $0, ext: "der")
    }
    return .init(trustedCerts: certsData)
  }

  var documentStorageServiceName: String {
    guard let identifier = Bundle.main.bundleIdentifier else {
      return "eudi.document.storage"
    }
    return "\(identifier).eudi.document.storage"
  }

  var logFileName: String {
    return "eudi-ios-wallet-logs"
  }

  var rpCertificatesUrl: URL? {
    switch configLogic.appBuildVariant {
    case .AU, .IN, .DEV:
      return URL(string: "https://verifier2.theaustraliahack.com/.well-known/rp-certificates")
    case .DEMO:
      return nil
    }
  }

  var documentsCategories: DocumentCategories {
    [
      .Government: [
        .mDocPid,
        .sdJwtPid,
        .other(formatType: "org.iso.18013.5.1.mDL"),
        .other(formatType: "eu.europa.ec.eudi.pseudonym.age_over_18.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:pseudonym_age_over_18:1"),
        .other(formatType: "eu.europa.ec.eudi.tax.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:tax:1"),
        .other(formatType: "eu.europa.ec.eudi.pseudonym.age_over_18.deferred_endpoint"),
        .other(formatType: "eu.europa.ec.eudi.cor.1")
      ],
      .Travel: [
        .other(formatType: "org.iso.23220.2.photoid.1"),
        .other(formatType: "org.iso.23220.photoID.1"),
        .other(formatType: "org.iso.18013.5.1.reservation")
      ],
      .Finance: [
        .other(formatType: "eu.europa.ec.eudi.iban.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:iban:1")
      ],
      .Education: [],
      .Health: [
        .other(formatType: "eu.europa.ec.eudi.hiid.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:hiid:1"),
        .other(formatType: "eu.europa.ec.eudi.ehic.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:ehic:1")
      ],
      .SocialSecurity: [
        .other(formatType: "eu.europa.ec.eudi.pda1.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:pda1:1")
      ],
      .Retail: [
        .other(formatType: "eu.europa.ec.eudi.loyalty.1"),
        .other(formatType: "eu.europa.ec.eudi.msisdn.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:msisdn:1")
      ],
      .Other: [
        .other(formatType: "eu.europa.ec.eudi.por.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:por:1")
      ]
    ]
  }

  var transactionLogger: any TransactionLogger {
    return self.transactionLoggerImpl
  }

  var revocationInterval: TimeInterval {
    300
  }

  var documentIssuanceConfig: DocumentIssuanceConfig {
    DocumentIssuanceConfig(
      defaultRule: DocumentIssuanceRule(
        policy: .rotateUse,
        numberOfCredentials: 1
      ),
      documentSpecificRules: [
        DocumentTypeIdentifier.mDocPid: DocumentIssuanceRule(
          policy: .oneTimeUse,
          numberOfCredentials: 10
        ),
        DocumentTypeIdentifier.sdJwtPid: DocumentIssuanceRule(
          policy: .oneTimeUse,
          numberOfCredentials: 10
        )
      ]
    )
  }
}
