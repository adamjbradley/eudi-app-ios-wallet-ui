# iOS Dynamic RP Certificate Trust — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fetch verifier (RP) certificates from `https://verifier2.theaustraliahack.com/.well-known/rp-certificates` at wallet startup, cache them on disk, and merge them into `EudiWallet.trustedReaderCertificates` — matching the Android `ReaderTrustStoreUpdater` behaviour so the iOS wallet stops rejecting verify requests from RPs with self-signed dev certs.

**Architecture:** New `ReaderTrustStoreUpdater` class in `Modules/logic-core/Sources/Config/` with URLSession-based fetch, `Application Support/rp-certificates-cache.pem` fallback, SHA-256 dedup. Per-flavor opt-in via `rpCertificatesUrl: URL?` on `WalletKitConfig`. `WalletKitController` fires a detached Task at init that union-merges bundled + fetched certs into `walletKit.trustedReaderCertificates`. Bundled DERs (`verifier2_theaustraliahack.der`, `rp_theaustraliahack.der`) stay as the cold-start / offline floor.

**Tech Stack:** Swift 6, iOS 17+, URLSession, CryptoKit (SHA-256), Swift Testing framework (XCTest-compatible via `@testable` + `EudiTest` base class).

**Design doc:** `docs/plans/2026-04-20-ios-dynamic-rp-certs-design.md`

**Worktree:** `/Users/adambradley/Projects/Mastercard/EUDI/eudi-app-ios-wallet-ui/.worktrees/multi-country-ios-flavors` (branch `feature/multi-country-ios-flavors`). No new worktree needed.

**TDD discipline:** Red → Green → Commit for each unit. Integration tasks at the end once the unit layer holds.

---

## Task 1: Add test target to `logic-core`

**Files:**
- Modify: `Modules/logic-core/Package.swift`
- Create: `Modules/logic-core/Tests/Placeholder.swift` (deleted in Task 2; exists so SwiftPM recognises the target before real tests land)

**Step 1: Edit `Package.swift`**

Add `logic-test` to `dependencies` (after the existing `logic-api` entry):

```swift
.package(name: "logic-test", path: "./logic-test")
```

And append a test target after the existing `.target(name: "logic-core", …)` entry, inside `targets: [ … ]`:

```swift
.testTarget(
  name: "logic-core-tests",
  dependencies: [
    "logic-core",
    "logic-test"
  ],
  path: "./Tests"
)
```

**Step 2: Write placeholder**

Create `Modules/logic-core/Tests/Placeholder.swift`:

```swift
import XCTest
@testable import logic_core

final class PlaceholderTests: XCTestCase {
  func testPackageBuilds() {
    XCTAssertTrue(true)
  }
}
```

**Step 3: Verify SwiftPM resolves**

Run: `cd Modules/logic-core && xcrun swift test --parallel 2>&1 | tail -20`

Expected: `Test Suite 'PlaceholderTests' passed` OR a compiler error about missing `logic_test` visibility (that's fine — we're just confirming SwiftPM recognises the test target; Xcode runs tests, not swift CLI, for app modules that depend on iOS-only frameworks).

If the CLI can't resolve iOS-only deps, skip and verify via Xcode: open `EudiReferenceWallet.xcodeproj`, Cmd+U on `logic-core-tests`, expect green.

**Step 4: Commit**

```bash
git add Modules/logic-core/Package.swift Modules/logic-core/Tests/Placeholder.swift
git commit -m "chore(logic-core): scaffold test target"
```

---

## Task 2: PEM parser — failing test

**Files:**
- Create: `Modules/logic-core/Tests/ReaderTrustStoreUpdaterTests.swift`
- Delete: `Modules/logic-core/Tests/Placeholder.swift`

**Step 1: Write failing test**

Create `Modules/logic-core/Tests/ReaderTrustStoreUpdaterTests.swift`:

```swift
import XCTest
@testable import logic_core

final class ReaderTrustStoreUpdaterTests: XCTestCase {

  // Two distinct self-signed test certs (trimmed PEM bodies; full values below)
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
    XCTAssertGreaterThan(ders[0].count, 50) // DER is > 50 bytes
    XCTAssertGreaterThan(ders[1].count, 50)
    XCTAssertNotEqual(ders[0], ders[1])
  }
}
```

Delete placeholder: `rm Modules/logic-core/Tests/Placeholder.swift`

**Step 2: Run, confirm fails to compile**

Open Xcode, Cmd+U on `logic-core-tests`.

Expected: **FAIL** with `cannot find 'ReaderTrustStoreUpdater' in scope`.

**Step 3: No commit yet** — TDD red phase.

---

## Task 3: PEM parser — minimal implementation

**Files:**
- Create: `Modules/logic-core/Sources/Config/ReaderTrustStoreUpdater.swift`

**Step 1: Write the class with just the parser**

```swift
/*
 * Copyright (c) 2025 European Commission
 * ...standard licence header...
 */
import Foundation

public final class ReaderTrustStoreUpdater: Sendable {

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
}
```

**Step 2: Run test — confirm passes**

Cmd+U in Xcode. Expected: `PASS`.

**Step 3: Commit**

```bash
git add Modules/logic-core/Sources/Config/ReaderTrustStoreUpdater.swift \
        Modules/logic-core/Tests/ReaderTrustStoreUpdaterTests.swift
git rm Modules/logic-core/Tests/Placeholder.swift
git commit -m "feat(logic-core): add ReaderTrustStoreUpdater.parsePem"
```

---

## Task 4: PEM parser — rejects garbage

**Files:**
- Modify: `Modules/logic-core/Tests/ReaderTrustStoreUpdaterTests.swift`

**Step 1: Add failing test**

Append to the test class:

```swift
func testParsePemRejectsNonCertText() {
  XCTAssertEqual(ReaderTrustStoreUpdater.parsePem(""), [])
  XCTAssertEqual(ReaderTrustStoreUpdater.parsePem("not a cert"), [])
  XCTAssertEqual(ReaderTrustStoreUpdater.parsePem("-----BEGIN WRONG-----\nAAAA\n-----END WRONG-----"), [])
}
```

**Step 2: Run — expected PASS** (parser already handles these cases via `compactMap` + guard)

**Step 3: Commit**

```bash
git commit -am "test(logic-core): parsePem rejects non-cert text"
```

---

## Task 5: Dedup — failing test

**Files:**
- Modify: `Modules/logic-core/Tests/ReaderTrustStoreUpdaterTests.swift`

**Step 1: Add failing test**

```swift
func testDeduplicateKeepsUniqueDropsDuplicates() {
  let a = ReaderTrustStoreUpdater.parsePem(Self.pemBlockA).first!
  let b = ReaderTrustStoreUpdater.parsePem(Self.pemBlockB).first!
  let input = [a, b, a, b, a]
  let deduped = ReaderTrustStoreUpdater.deduplicateByFingerprint(input)
  XCTAssertEqual(deduped.count, 2)
  XCTAssertTrue(deduped.contains(a))
  XCTAssertTrue(deduped.contains(b))
}
```

**Step 2: Run — FAIL** with `cannot find 'deduplicateByFingerprint'`.

**Step 3: No commit.**

---

## Task 6: Dedup — implementation

**Files:**
- Modify: `Modules/logic-core/Sources/Config/ReaderTrustStoreUpdater.swift`

**Step 1: Add CryptoKit import + dedup function**

At top of file, add `import CryptoKit`. Inside the class:

```swift
/// Deduplicate by SHA-256 fingerprint of the DER bytes. Identical to the
/// Android `ReaderTrustStoreUpdater.deduplicateByFingerprint` definition —
/// the same cert bundled locally and fetched from the URL collapses to one.
public static func deduplicateByFingerprint(_ certs: [Data]) -> [Data] {
  var seen = Set<Data>()
  return certs.filter { cert in
    let fingerprint = Data(SHA256.hash(data: cert))
    return seen.insert(fingerprint).inserted
  }
}
```

**Step 2: Run — PASS.**

**Step 3: Commit**

```bash
git commit -am "feat(logic-core): add deduplicateByFingerprint"
```

---

## Task 7: Cache URL — failing test

**Files:**
- Modify: `Modules/logic-core/Tests/ReaderTrustStoreUpdaterTests.swift`

**Step 1: Add failing test**

```swift
func testCacheURLIsUnderApplicationSupport() throws {
  let url = try ReaderTrustStoreUpdater.cacheURL()
  let path = url.path
  XCTAssertTrue(path.contains("Application Support"), "got \(path)")
  XCTAssertTrue(path.hasSuffix("rp-certificates-cache.pem"))
}
```

**Step 2: FAIL** (`cacheURL` not defined).

---

## Task 8: Cache URL — implementation

**Files:**
- Modify: `Modules/logic-core/Sources/Config/ReaderTrustStoreUpdater.swift`

**Step 1: Add function**

```swift
public static func cacheURL() throws -> URL {
  let dir = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
  )
  return dir.appendingPathComponent("rp-certificates-cache.pem")
}
```

**Step 2: Run — PASS.**

**Step 3: Commit**

```bash
git commit -am "feat(logic-core): add cacheURL under Application Support"
```

---

## Task 9: Network success — failing test with URLProtocol stub

**Files:**
- Modify: `Modules/logic-core/Tests/ReaderTrustStoreUpdaterTests.swift`

**Step 1: Add URLProtocol stub + failing test**

At end of the test file, add:

```swift
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var payload: Data = Data()
  nonisolated(unsafe) static var statusCode: Int = 200
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let resp = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.payload)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

extension ReaderTrustStoreUpdaterTests {
  func testFetchCertificatesReturnsParsedDersOnHttp200() async throws {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: cfg)

    StubURLProtocol.statusCode = 200
    StubURLProtocol.payload = (Self.pemBlockA + "\n" + Self.pemBlockB).data(using: .utf8)!

    // Use a temp cache path so we don't pollute Application Support during tests
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rp-\(UUID()).pem")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let updater = ReaderTrustStoreUpdater(
      pemUrl: URL(string: "https://example.invalid/.well-known/rp-certificates")!,
      session: session,
      cacheURL: tmp
    )
    let ders = await updater.fetchCertificates()
    XCTAssertEqual(ders.count, 2)
    XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
  }
}
```

**Step 2: FAIL** — initialiser signature doesn't exist.

---

## Task 10: Network success — initialiser + `fetchCertificates` + `downloadPem`

**Files:**
- Modify: `Modules/logic-core/Sources/Config/ReaderTrustStoreUpdater.swift`

**Step 1: Replace class body**

```swift
public final class ReaderTrustStoreUpdater: Sendable {
  private let pemUrl: URL
  private let session: URLSession
  private let cacheURL: URL
  private static let connectTimeout: TimeInterval = 10
  private static let readTimeout: TimeInterval = 15

  /// - Parameters:
  ///   - pemUrl: endpoint returning a PEM bundle (one or more `CERTIFICATE` blocks)
  ///   - session: URLSession to use for the fetch — defaults to a transient ephemeral session
  ///   - cacheURL: override for the on-disk cache path (test seam); defaults to `Self.cacheURL()`
  public init(
    pemUrl: URL,
    session: URLSession = URLSession(configuration: .ephemeral),
    cacheURL: URL? = nil
  ) {
    self.pemUrl = pemUrl
    self.session = session
    self.cacheURL = cacheURL ?? ((try? Self.cacheURL()) ?? URL(fileURLWithPath: "/dev/null"))
  }

  public func fetchCertificates() async -> [Data] {
    if let pem = try? await downloadPem(), !pem.isEmpty {
      try? pem.write(to: cacheURL, atomically: true, encoding: .utf8)
      return Self.parsePem(pem)
    }
    if let cached = try? String(contentsOf: cacheURL, encoding: .utf8) {
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

  // parsePem / deduplicateByFingerprint / cacheURL — from earlier tasks
}
```

**Step 2: Run — PASS.**

**Step 3: Commit**

```bash
git commit -am "feat(logic-core): fetchCertificates with URLSession + disk cache"
```

---

## Task 11: Cache fallback — failing test

**Files:**
- Modify: `Modules/logic-core/Tests/ReaderTrustStoreUpdaterTests.swift`

**Step 1: Add failing test**

```swift
func testFetchFallsBackToCacheOnNetworkError() async throws {
  let cfg = URLSessionConfiguration.ephemeral
  cfg.protocolClasses = [StubURLProtocol.self]
  let session = URLSession(configuration: cfg)

  StubURLProtocol.statusCode = 500
  StubURLProtocol.payload = Data()

  let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rp-\(UUID()).pem")
  try (Self.pemBlockA).data(using: .utf8)!.write(to: tmp)
  defer { try? FileManager.default.removeItem(at: tmp) }

  let updater = ReaderTrustStoreUpdater(
    pemUrl: URL(string: "https://example.invalid/.well-known/rp-certificates")!,
    session: session,
    cacheURL: tmp
  )
  let ders = await updater.fetchCertificates()
  XCTAssertEqual(ders.count, 1, "should have fallen back to cache")
}

func testFetchReturnsEmptyOnFailureWithNoCache() async throws {
  let cfg = URLSessionConfiguration.ephemeral
  cfg.protocolClasses = [StubURLProtocol.self]
  let session = URLSession(configuration: cfg)

  StubURLProtocol.statusCode = 500

  let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rp-nonexistent-\(UUID()).pem")

  let updater = ReaderTrustStoreUpdater(
    pemUrl: URL(string: "https://example.invalid/.well-known/rp-certificates")!,
    session: session,
    cacheURL: tmp
  )
  let ders = await updater.fetchCertificates()
  XCTAssertEqual(ders, [])
}
```

**Step 2: Run — PASS** (fallback logic already present from Task 10). If tests accidentally drive through happy path, verify `StubURLProtocol.statusCode = 500` path returns empty from `downloadPem`.

**Step 3: Commit**

```bash
git commit -am "test(logic-core): cache fallback on network failure + empty on miss"
```

---

## Task 12: `rpCertificatesUrl` on `WalletKitConfig`

**Files:**
- Modify: `Modules/logic-core/Sources/Config/WalletKitConfig.swift`
- Modify: `Modules/logic-core/Tests/ReaderTrustStoreUpdaterTests.swift` (no — defer tests; config is a simple switch)

**Step 1: Add protocol member**

In `public protocol WalletKitConfig`, add:

```swift
/// URL of a PEM bundle listing trusted RP/verifier certificates.
/// Return `nil` to disable dynamic fetching for a flavor.
var rpCertificatesUrl: URL? { get }
```

**Step 2: Implement on `WalletKitConfigImpl`**

Add inside the impl:

```swift
var rpCertificatesUrl: URL? {
  switch configLogic.appBuildVariant {
  case .AU, .IN, .DEV:
    return URL(string: "https://verifier2.theaustraliahack.com/.well-known/rp-certificates")
  case .DEMO:
    return nil
  }
}
```

**Step 3: Update mocks**

Grep for mock implementations and add the property:

Run: `grep -l "class MockWalletKitConfig\|MockWalletKitConfig:" Modules --include="*.swift" -r`

For each file found, add `var rpCertificatesUrl: URL? { nil }` to the mock.

**Step 4: Build — Cmd+B in Xcode on `EudiWallet` scheme**

Expected: **BUILD SUCCEEDED** (green).

**Step 5: Commit**

```bash
git commit -am "feat(logic-core): add rpCertificatesUrl to WalletKitConfig"
```

---

## Task 13: Wire updater into `WalletKitController`

**Files:**
- Modify: `Modules/logic-core/Sources/Controller/WalletKitController.swift`

**Step 1: Add the background fetch at end of init**

Locate the `init(...)` that ends with `wallet = walletKit`. Insert before that assignment (or just after, conceptually equivalent):

```swift
// Dynamic refresh of trusted reader certificates (if a URL is configured for
// this flavor). Matches Android's CoroutineScope(Dispatchers.IO).launch —
// fire-and-forget, bundled certs stay authoritative until the fetch lands.
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

**Step 2: Build**

Cmd+B on `EudiWallet`. Expected: **BUILD SUCCEEDED**.

**Step 3: Commit**

```bash
git commit -am "feat(logic-core): dynamically refresh trusted reader certs at startup"
```

---

## Task 14: On-device integration verification

No code changes — smoke test.

**Step 1: Run local archive** (skip fastlane for the fast loop)

```bash
cd /Users/adambradley/Projects/Mastercard/EUDI/eudi-app-ios-wallet-ui/.worktrees/multi-country-ios-flavors
UDID=$(xcrun xctrace list devices 2>/dev/null | grep -E "iPhone" | grep -v Simulator | head -1 | grep -oE "[0-9A-F]{8}-[0-9A-F]+")
xcodebuild -project EudiReferenceWallet.xcodeproj -scheme "EUDI Wallet AU" \
  -configuration "Release AU" \
  -destination "platform=iOS,id=$UDID" \
  -allowProvisioningUpdates build
```

**Step 2: Install + launch**

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData/EudiReferenceWallet-*/Build/Products/Release\ AU-iphoneos -name EudiWallet.app -type d | head -1)
xcrun devicectl device install app --device $UDID "$APP"
```

**Step 3: Retrieve log + verify fetch happened**

Reproduce the Portal Verify flow once. Then:

```bash
xcrun devicectl device copy from --device $UDID \
  --source "Library/Application Support/rp-certificates-cache.pem" \
  --domain-type appDataContainer \
  --domain-identifier eu.europa.ec.euidi.au \
  --destination /tmp/rp-cache.pem
cat /tmp/rp-cache.pem | grep -c "BEGIN CERTIFICATE"
```

Expected: **`2`** (the two self-signed certs from the endpoint).

**Step 4: Verify verify succeeds**

Portal Verify → scan QR → wallet displays consent sheet (not "requested document is not available"). Accept → verifier returns success.

**Step 5: Offline-cache regression**

Enable airplane mode on iPhone. Kill + relaunch wallet. Repeat verify. Expected: **still succeeds** because the cache file was populated during Step 3.

**Step 6: No commit** (this is verification, not a change).

---

## Task 15: Remove the static-bundle patch

Once Task 14 passes on-device, unwind the stopgap (`b9303c3c`). The dynamic fetch + cache provides the same trust without the yearly-manual-rebundle burden.

**Files:**
- Delete: `Wallet/Certificate/verifier2_theaustraliahack.der`
- Delete: `Wallet/Certificate/rp_theaustraliahack.der`
- Modify: `Modules/logic-core/Sources/Config/WalletKitConfig.swift` — remove the two new names from the `certificates` array
- Modify: `EudiReferenceWallet.xcodeproj/project.pbxproj` — remove the 4 `C1EE27A0…` entries

**Step 1: Decide — keep or drop the static bundle?**

**The design doc says keep them** (Android does, for first-launch-offline). **Follow the design doc.** Skip this task entirely.

Only do this task if a subsequent decision changes the policy (e.g., "dev certs are tiny, move them to a `docs/` reference and prove the dynamic path handles everything"). In that case:

```bash
git rm Wallet/Certificate/verifier2_theaustraliahack.der Wallet/Certificate/rp_theaustraliahack.der
# edit WalletKitConfig.swift and project.pbxproj
git commit -m "chore: drop static dev-cert bundle, dynamic fetch owns trust"
```

---

## Task 16: Remove diagnostic code

Once Task 14 is green, the `DiagnosticLogHandler` + `RemoteSessionCoordinator` NSLog traces are dead weight. Revert them as a single commit so the history is bisectable.

**Files:**
- Modify: `Wallet/AppDelegate.swift` — restore to pre-`DiagnosticLogHandler` state
- Modify: `Modules/logic-core/Sources/Coordinator/RemoteSessionCoordinator.swift` — revert NSLog lines
- Modify: `Modules/logic-core/Sources/Controller/WalletKitController.swift` — remove the `// NOTE: do NOT reassign walletKit.logFileName` comment block (no longer relevant)

**Step 1: Revert**

```bash
git log --oneline | head -20   # identify the three diagnostic commits
# For each of: c3acffb3, d36059c9, 1ed689f8 — cherry-revert or hand-edit
```

Suggested: open the three commits in a viewer and hand-edit the affected files back, rather than `git revert` which would conflict with the cert-trust fix that landed between.

**Step 2: Build**

Cmd+B on `EudiWallet`. Expected: **BUILD SUCCEEDED**.

**Step 3: Commit**

```bash
git commit -am "chore(diag): remove NSLog multiplex handler + session traces"
```

---

## Task 17: Deploy

**Step 1:** `cd <worktree> && doppler run --project infrastructure-dev --config dev -- fastlane deploy_all`

**Step 2:** Wait for both `** ARCHIVE SUCCEEDED **` in `~/Library/Logs/gym/EudiWallet-EUDI\ Wallet\ AU.log` and `…IN.log`.

**Step 3:** Install build from TestFlight on the test iPhone (5–15 min after upload).

**Step 4:** Repeat Task 14 steps 3 – 5 as final acceptance.

---

## Rollback plan

If Task 14 fails (dynamic fetch doesn't land the certs, or introduces a regression):

1. `git revert` the commits from Tasks 12 + 13 (`WalletKitConfig` property add + controller wire-in) in a single revert commit.
2. The static `verifier2_theaustraliahack.der` + `rp_theaustraliahack.der` remain bundled (commit `b9303c3c`), so the wallet still trusts the verifier.
3. Redeploy — back to known-working state.
