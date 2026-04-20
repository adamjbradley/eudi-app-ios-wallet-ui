# iOS dynamic RP certificate trust — design

## Problem

The iOS wallet rejects verify requests from `verifier2.theaustraliahack.com` with `MdocSecurity18013: "verifier2.theaustraliahack.com" certificate is not trusted → Validation Error Could not trust certificate chain`. The UI masks this as a generic "requested document is not available" error. Android handles the same verifier fine because it dynamically fetches the verifier's self-signed certs from `https://verifier2.theaustraliahack.com/.well-known/rp-certificates` at startup and adds them to the wallet's trusted-reader list. iOS has no equivalent mechanism — its `readerConfig.trustedCerts` is a static bundle of EU PID issuer CAs only.

A short-term patch (commit `b9303c3c`) bundles the two self-signed DERs statically. That works but drifts every time a cert is re-issued (they expire yearly) and requires a full app release to update the trust list. Android's dynamic-fetch pattern is the right long-term design.

## Approach

Mirror Android's `ReaderTrustStoreUpdater` on iOS — per-flavor opt-in URL, fetch-once-at-startup, on-disk PEM cache, silent fallback chain. Merge the fetched certs with the bundled ones rather than replacing, so first-launch-offline still has a working trust floor. Expose `rpCertificatesUrl: URL?` on `WalletKitConfig`; return a value for `.AU`/`.IN`/`.DEV`, `nil` for `.DEMO`.

## Configuration surface

```swift
// Modules/logic-core/Sources/Config/WalletKitConfig.swift
public protocol WalletKitConfig: Sendable {
  // … existing …
  var rpCertificatesUrl: URL? { get }
}

extension WalletKitConfigImpl {
  var rpCertificatesUrl: URL? {
    switch configLogic.appBuildVariant {
    case .AU, .IN, .DEV:
      return URL(string: "https://verifier2.theaustraliahack.com/.well-known/rp-certificates")
    case .DEMO:
      return nil
    }
  }
}
```

`.DEMO` opts out — it targets `issuer.eudiw.dev` with its own trust list; re-trusting our dev verifier there would be wrong. `URL?` not `String?` because we parse once at config time, not deferred per-use.

## `ReaderTrustStoreUpdater`

New file `Modules/logic-core/Sources/Config/ReaderTrustStoreUpdater.swift`, direct analogue of Android's class at the same path.

```swift
import Foundation
import CryptoKit

public final class ReaderTrustStoreUpdater: Sendable {
  private let pemUrl: URL
  private let session: URLSession
  private static let cacheFileName = "rp-certificates-cache.pem"
  private static let connectTimeout: TimeInterval = 10
  private static let readTimeout: TimeInterval = 15

  public init(pemUrl: URL, session: URLSession = .shared) {
    self.pemUrl = pemUrl
    self.session = session
  }

  public func fetchCertificates() async -> [Data] {
    if let pem = try? await downloadPem(), !pem.isEmpty {
      try? pem.write(to: cacheURL(), atomically: true, encoding: .utf8)
      return parsePem(pem)
    }
    if let cached = try? String(contentsOf: cacheURL(), encoding: .utf8) {
      return parsePem(cached)
    }
    return []
  }

  public static func deduplicateByFingerprint(_ certs: [Data]) -> [Data] {
    var seen = Set<Data>()
    return certs.filter { seen.insert(Data(SHA256.hash(data: $0))).inserted }
  }

  // downloadPem / parsePem / cacheURL — PEM header strip + base64 decode per block
}
```

| Decision | Choice | Why |
|---|---|---|
| Return type | `[Data]` (DER bytes) | `EudiWallet.trustedReaderCertificates` is `[Data]?` — no `SecCertificate` conversion needed |
| Cache location | `Application Support/rp-certificates-cache.pem` | iOS analogue of Android `filesDir`; not `Caches/` (OS-evictable), not `Documents/` (iCloud-backed, user-visible) |
| Cache filename | `rp-certificates-cache.pem` | Matches Android exactly |
| Timeouts | 10s connect / 15s read | Matches Android constants |
| Dedup | SHA-256 of DER bytes | Identical fingerprint definition to Android |
| PEM parse | Split on `-----END CERTIFICATE-----`, strip headers, base64-decode | ~15 lines, no third-party dep |

## Integration

```swift
// Modules/logic-core/Sources/Controller/WalletKitController.swift
// … existing init …

if let url = configLogic.rpCertificatesUrl {
  let bundled = configLogic.readerConfig.trustedCerts
  Task.detached(priority: .utility) { [weak walletKit] in
    let fetched = await ReaderTrustStoreUpdater(pemUrl: url).fetchCertificates()
    guard !fetched.isEmpty, let walletKit else { return }
    walletKit.trustedReaderCertificates =
      ReaderTrustStoreUpdater.deduplicateByFingerprint(bundled + fetched)
  }
}
```

- **Bundled-first, fetched-later**: wallet is usable the instant init returns. Verifies arriving before the fetch completes use the static trust floor.
- **Union, not replace**: `bundled + fetched` deduped. Android appears to replace; we keep the bundle as a guaranteed floor because network-flaky first launches shouldn't wipe trust.
- **`Task.detached`**: escape init's actor context; this is genuine background work.
- **`[weak walletKit]`**: in case the wallet is deallocated during a long fetch.
- **Silent failure**: `fetchCertificates()` returns `[]` on any failure; caller guard skips the update; bundled certs remain authoritative. No UI surface.

## Failure modes

| Failure mode | Result |
|---|---|
| Network unreachable, cache exists | Use cached PEM (log age) |
| Network unreachable, no cache | Return empty → wallet keeps bundled certs |
| Server returns 4xx/5xx | Same as unreachable |
| PEM bundle malformed | `parsePem` returns empty → wallet keeps bundled certs |
| Cache file corrupted | `parsePem` returns empty → log + fall through to bundled |

## Testing

- **`Modules/logic-core/Tests/ReaderTrustStoreUpdaterTests.swift`** — multi-block PEM parse, malformed PEM returns empty, dedup on identical + distinct DER, cache fallback on network failure, cache corruption tolerated. Stub `URLSession` via `URLProtocol`; use tmpDir override for cache.
- **On-device integration** — install new build, delete the two statically-bundled DERs locally, confirm first verify still succeeds (proves dynamic path is live); then airplane-mode + relaunch, verify offline (proves cache fallback).
- **Regression** — `.DEMO` (which returns `nil`) still verifies against the EU PID CAs only.

## Rollout

1. Implement updater + tests.
2. Wire into `WalletKitController`.
3. `fastlane deploy_all` → AU/IN next build.
4. Once verified on TestFlight, revert the diagnostic commits (`DiagnosticLogHandler`, `RemoteSessionCoordinator` NSLog traces) in a separate commit so each step is bisectable.
5. Keep the bundled `verifier2_theaustraliahack.der` + `rp_theaustraliahack.der` — they're the offline / first-launch trust floor. Android bundles + fetches for the same reason.

## Out of scope

- Revocation / CRL / OCSP — Android doesn't do this for dev certs either.
- Timer-based auto-refresh — Android only fetches at launch; match that. Re-launch is the refresh mechanism.
- UI surface to inspect cached cert fingerprints — defer until there's a debugging need.
- Migrating away from self-signed certs entirely — separate concern; the PKI strategy is owned by the RP side.
