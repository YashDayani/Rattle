import AppKit
import CryptoKit
import XCTest
@testable import Rattle

/// The updater: version order, release parsing, the checksum list, the GitHub-only rule, signed updates, and full runs against local files
/// (verify, unpack, validate, hand-off), including tampered, forged and look-alike downloads.
@MainActor
final class UpdaterTests: XCTestCase {
    private let fm = FileManager.default
    private var work: URL!
    private var upd: Updater!
    private var handedOff: URL?
    private let pageURL = URL(string: "https://github.com/a/b")!

    override func setUp() async throws {
        work = fm.temporaryDirectory.appendingPathComponent("rattle-updater-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        handedOff = nil
        upd = Updater()
        upd.isTrustedDownload = { _ in true }
        upd.checkSigner = { _ in .matches }
        upd.publicKey = nil
        upd.defaults = UserDefaults(suiteName: "rattle-updater-test-\(UUID().uuidString)")!
        upd.autoCheckEnabled = { true }
        upd.presentDialog = {}
        upd.currentVersion = "1.0.0"
        upd.expectedBundleID = "com.rattle.app"
        upd.appURL = work.appendingPathComponent("Installed/Rattle.app")
        try fm.createDirectory(at: upd.appURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        upd.relaunch = { [unowned self] _, newApp in handedOff = newApp; return false }   // never quit the test process
    }

    override func tearDown() async throws { try? fm.removeItem(at: work) }

    // MARK: helpers

    private func v(_ s: String) -> AppVersion { AppVersion(s)! }

    private func sh(_ exe: String, _ args: [String]) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try! p.run(); p.waitUntilExit()
    }

    /// A tiny ad-hoc signed app with the given version, zipped the way the release workflow does it.
    private func makeRelease(version: String, bundleID: String = "com.rattle.app", in dir: URL) -> (zip: URL, sums: URL) {
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let app = dir.appendingPathComponent("Rattle.app")
        try? fm.removeItem(at: app)
        try! fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let exe = app.appendingPathComponent("Contents/MacOS/Rattle")
        try! "#!/bin/sh\nexit 0\n".write(to: exe, atomically: true, encoding: .utf8)
        sh("/bin/chmod", ["+x", exe.path])
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version, "CFBundleExecutable": "Rattle", "CFBundlePackageType": "APPL"]
        (plist as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        sh("/usr/bin/codesign", ["--force", "--deep", "-s", "-", app.path])
        let zip = dir.appendingPathComponent("Rattle.zip")
        try? fm.removeItem(at: zip)
        sh("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
        let sums = dir.appendingPathComponent("SHA256SUMS")
        try! "\(try! Updater.sha256(of: zip))  Rattle.zip\n".write(to: sums, atomically: true, encoding: .utf8)
        return (zip, sums)
    }

    private func offer(_ zip: URL, _ sums: URL?, sig: URL? = nil, version: String = "1.1.0") -> UpdateOffer {
        UpdateOffer(version: version, notes: "", pageURL: pageURL, zipURL: zip, sumsURL: sums, size: 1, sigURL: sig)
    }

    private func releaseJSON(tag: String = "v1.2.0", draft: Bool = false, pre: Bool = false,
                             assets: [(String, String)] = [("Rattle.zip", "https://github.com/a/b/releases/download/v1.2.0/Rattle.zip"), ("SHA256SUMS", "https://github.com/a/b/releases/download/v1.2.0/SHA256SUMS")]) -> Data {
        let a = assets.map { "{\"name\":\"\($0.0)\",\"browser_download_url\":\"\($0.1)\",\"size\":1234}" }.joined(separator: ",")
        return Data("{\"tag_name\":\"\(tag)\",\"body\":\"## Notes\\n- fix\",\"html_url\":\"https://github.com/a/b/releases/tag/\(tag)\",\"draft\":\(draft),\"prerelease\":\(pre),\"assets\":[\(a)]}".utf8)
    }

    private func parsed(_ d: Data) -> UpdateOffer? { (try? Updater.parseRelease(d)) ?? nil }

    /// Runs an install and returns "installed" when it reached the (declined) hand-off, else the failure text or the state.
    private func attempt(_ o: UpdateOffer) async -> String {
        handedOff = nil
        upd.state = .idle; upd.install(o)
        for _ in 0..<200 {
            if case .failed = upd.state { break }
            if case .revealed = upd.state { break }
            if handedOff != nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if handedOff != nil { return "installed" }
        if case .failed(let m) = upd.state { return m }
        return "\(upd.state)"
    }

    private func sign(_ zip: URL, with key: Curve25519.Signing.PrivateKey, as name: String) -> URL {
        let out = zip.deletingLastPathComponent().appendingPathComponent(name)
        try! key.signature(for: try! Data(contentsOf: zip)).base64EncodedString().write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    // MARK: versions, releases, checksums

    func testVersionOrdering() {
        XCTAssertTrue(v("1.10.0") > v("1.9.9"))
        XCTAssertEqual(v("v1.2.0"), v("1.2.0"))
        XCTAssertEqual(v("1.2"), v("1.2.0"))
        XCTAssertTrue(v("1.3.0-beta.1") < v("1.3.0"))
        XCTAssertTrue(v("1.3.0-beta.1") < v("1.3.0-beta.2"))
        XCTAssertNil(AppVersion("latest")); XCTAssertNil(AppVersion("")); XCTAssertNil(AppVersion("1.x"))
    }

    func testReleaseParsing() {
        let o = parsed(releaseJSON())
        XCTAssertEqual(o?.version, "1.2.0"); XCTAssertEqual(o?.size, 1234)
        XCTAssertNotNil(o?.sumsURL); XCTAssertEqual(o?.notes.contains("fix"), true)
        XCTAssertNil(parsed(releaseJSON(draft: true))); XCTAssertNil(parsed(releaseJSON(pre: true)))
        XCTAssertNil(parsed(releaseJSON(assets: [("Other.zip", "https://github.com/x")])))
        XCTAssertNil(parsed(releaseJSON(tag: "nightly")))
        let signed = parsed(releaseJSON(assets: [("Rattle.zip", "https://github.com/a/b/z"), ("SHA256SUMS", "https://github.com/a/b/s"), ("Rattle.zip.sig", "https://github.com/a/b/g")]))
        XCTAssertEqual(signed?.sigURL?.lastPathComponent, "g"); XCTAssertNil(parsed(releaseJSON())?.sigURL)
    }

    func testChecksumList() {
        let h = String(repeating: "ab", count: 32)
        XCTAssertEqual(Updater.expectedSHA256(in: "\(h)  Rattle.zip\n", for: "Rattle.zip"), h)
        XCTAssertEqual(Updater.expectedSHA256(in: "\(h.uppercased()) *Rattle.zip", for: "Rattle.zip"), h)
        XCTAssertNil(Updater.expectedSHA256(in: "\(h)  Other.zip\n", for: "Rattle.zip"))
        XCTAssertNil(Updater.expectedSHA256(in: "abc  Rattle.zip", for: "Rattle.zip"))
        XCTAssertNil(Updater.expectedSHA256(in: "\(String(repeating: "zz", count: 32))  Rattle.zip", for: "Rattle.zip"))
    }

    func testOnlyGitHubOverHTTPSIsTrusted() {
        func trusted(_ s: String) -> Bool { Updater.isTrustedGitHubURL(URL(string: s)!) }
        XCTAssertTrue(trusted("https://github.com/a/b/releases/download/v1/Rattle.zip"))
        XCTAssertTrue(trusted("https://objects.githubusercontent.com/x"))
        for bad in ["http://github.com/x", "https://evil.example/x", "https://github.com.evil.example/x", "https://notgithub.com/x", "file:///tmp/x"] {
            XCTAssertFalse(trusted(bad), bad)
        }
    }

    func testInPlaceReplacementRule() {
        XCTAssertTrue(Updater.canReplace(work.appendingPathComponent("X.app")))
        XCTAssertFalse(Updater.canReplace(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/y/d/Rattle.app")))
    }

    func testSha256MatchesShasum() throws {
        let f = work.appendingPathComponent("blob"); try Data((0..<3_000_000).map { UInt8($0 % 251) }).write(to: f)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shasum"); p.arguments = ["-a", "256", f.path]
        let pipe = Pipe(); p.standardOutput = pipe; try p.run(); p.waitUntilExit()
        let want = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: " ").first.map(String.init)
        XCTAssertEqual(try Updater.sha256(of: f), want)
    }

    // MARK: checking

    func testCheckOffersOnlyNewerVersions() async throws {
        let feed = work.appendingPathComponent("latest.json"); try releaseJSON().write(to: feed)
        upd.releaseURL = feed
        let fetched = try await upd.fetchLatest()
        XCTAssertEqual(fetched?.version, "1.2.0")
        await upd.check(manual: true)
        guard case .available(let o) = upd.state else { return XCTFail("\(upd.state)") }
        XCTAssertEqual(o.version, "1.2.0")
        upd.currentVersion = "1.2.0"
        await upd.check(manual: true)
        XCTAssertEqual(upd.state, .upToDate)
    }

    func testSkippedVersionSilencesOnlyTheQuietCheck() async throws {
        let feed = work.appendingPathComponent("latest.json"); try releaseJSON().write(to: feed)
        upd.releaseURL = feed
        upd.skip(offer(feed, nil, version: "1.2.0"))
        await upd.check(manual: false)
        XCTAssertEqual(upd.state, .idle); XCTAssertFalse(upd.dialogVisible)
        await upd.check(manual: true)
        guard case .available = upd.state else { return XCTFail("\(upd.state)") }
    }

    func testLaunchCheckFindsTheUpdateAndRespectsTheSwitch() async throws {
        let feed = work.appendingPathComponent("latest.json"); try releaseJSON().write(to: feed)
        upd.releaseURL = feed
        upd.checkOnLaunch()
        for _ in 0..<100 { if case .available = upd.state { break }; try? await Task.sleep(nanoseconds: 50_000_000) }
        guard case .available = upd.state else { return XCTFail("\(upd.state)") }
        XCTAssertTrue(upd.dialogVisible)

        let off = Updater(); off.releaseURL = feed; off.currentVersion = "1.0.0"; off.presentDialog = {}
        off.defaults = UserDefaults(suiteName: "rattle-updater-test-\(UUID().uuidString)")!
        off.autoCheckEnabled = { false }
        off.checkOnLaunch(); try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(off.state, .idle)
    }

    // MARK: installing

    func testGoodUpdateReachesTheInstallerHandOff() async {
        let r = makeRelease(version: "1.1.0", in: work.appendingPathComponent("good"))
        let result = await attempt(offer(r.zip, r.sums))
        XCTAssertEqual(result, "installed"); XCTAssertEqual(handedOff?.lastPathComponent, "Rattle.app")
    }

    func testTamperedZipIsRejectedBeforeUnpacking() async {
        let r = makeRelease(version: "1.1.0", in: work.appendingPathComponent("bad"))
        let fh = try! FileHandle(forWritingTo: r.zip); try! fh.seekToEnd(); try! fh.write(contentsOf: Data([0, 1, 2])); try! fh.close()
        let result = await attempt(offer(r.zip, r.sums))
        XCTAssertTrue(result.contains("checksum"), result); XCTAssertNil(handedOff)
    }

    func testOtherBundleIdentifierAndOlderVersionAreRejected() async {
        let evil = makeRelease(version: "1.1.0", bundleID: "com.evil.app", in: work.appendingPathComponent("other"))
        let a = await attempt(offer(evil.zip, evil.sums))
        XCTAssertTrue(a.contains("not Rattle"), a); XCTAssertNil(handedOff)
        let same = makeRelease(version: "1.1.0", in: work.appendingPathComponent("same"))
        upd.currentVersion = "1.1.0"
        let b = await attempt(offer(same.zip, same.sums))
        XCTAssertTrue(b.contains("not newer"), b); XCTAssertNil(handedOff)
    }

    func testNoChecksumFileAndNonGitHubLocationsAreRefused() async {
        let r = makeRelease(version: "1.1.0", in: work.appendingPathComponent("g"))
        let none = await attempt(offer(r.zip, nil))
        XCTAssertTrue(none.contains("SHA256SUMS"), none)
        upd.isTrustedDownload = Updater.isTrustedGitHubURL
        let local = await attempt(offer(r.zip, r.sums))
        XCTAssertTrue(local.contains("not GitHub"), local)
    }

    func testSignerPinningAndReadOnlyLocation() async {
        let r = makeRelease(version: "1.1.0", in: work.appendingPathComponent("pin"))
        upd.checkSigner = { _ in .mismatch }
        let mismatch = await attempt(offer(r.zip, r.sums))
        XCTAssertTrue(mismatch.contains("different developer"), mismatch); XCTAssertNil(handedOff)
        upd.checkSigner = { _ in .cannotPin }
        let adhoc = await attempt(offer(r.zip, r.sums))
        XCTAssertEqual(adhoc, "installed")
        upd.checkSigner = { _ in .matches }
        upd.appURL = URL(fileURLWithPath: "/System/Applications/Rattle.app")
        handedOff = nil; upd.state = .idle; upd.install(offer(r.zip, r.sums))
        for _ in 0..<200 { if case .revealed = upd.state { break }; if case .failed = upd.state { break }; try? await Task.sleep(nanoseconds: 50_000_000) }
        guard case .revealed = upd.state else { return XCTFail("\(upd.state)") }
        XCTAssertNil(handedOff)
    }

    // MARK: signed updates

    func testOnlyAZipSignedWithTheAppKeyIsInstalled() async throws {
        let signer = Curve25519.Signing.PrivateKey(), stranger = Curve25519.Signing.PrivateKey()
        upd.publicKey = signer.publicKey.rawRepresentation
        let dir = work.appendingPathComponent("signed")
        let r = makeRelease(version: "1.1.0", in: dir)
        let good = sign(r.zip, with: signer, as: "good.sig")
        let ok = await attempt(offer(r.zip, r.sums, sig: good))
        XCTAssertEqual(ok, "installed")

        // an attacker who controls the release swaps the zip AND rewrites SHA256SUMS to match it
        let evil = dir.appendingPathComponent("Rattle.zip.evil"); try fm.copyItem(at: r.zip, to: evil)
        let fh = try FileHandle(forWritingTo: evil); try fh.seekToEnd(); try fh.write(contentsOf: Data([9, 9, 9])); try fh.close()
        let evilSums = dir.appendingPathComponent("evil-sums")
        try "\(try Updater.sha256(of: evil))  Rattle.zip\n".write(to: evilSums, atomically: true, encoding: .utf8)
        let forged = await attempt(offer(evil, evilSums, sig: good))
        XCTAssertTrue(forged.contains("signature is not valid"), forged)

        let byStranger = await attempt(offer(r.zip, r.sums, sig: sign(r.zip, with: stranger, as: "stranger.sig")))
        XCTAssertTrue(byStranger.contains("signature is not valid"), byStranger)
        let junk = dir.appendingPathComponent("junk.sig"); try "not a signature".write(to: junk, atomically: true, encoding: .utf8)
        let garbage = await attempt(offer(r.zip, r.sums, sig: junk))
        XCTAssertTrue(garbage.contains("signature is not valid"), garbage)
        let unsigned = await attempt(offer(r.zip, r.sums, sig: nil))
        XCTAssertTrue(unsigned.contains("isn’t signed"), unsigned)

        XCTAssertFalse(Updater.verifySignature(zip: r.zip, signatureBase64: "AAAA", publicKey: signer.publicKey.rawRepresentation))
        XCTAssertTrue(Updater.verifySignature(zip: r.zip, signatureBase64: try String(contentsOf: good), publicKey: signer.publicKey.rawRepresentation))
    }

    func testTheShippedPublicKeyIsWellFormed() throws {
        try XCTSkipIf(UpdateKey.publicKeyBase64.isEmpty, "update signing is not set up yet; the release workflow refuses to publish until it is")
        XCTAssertEqual(UpdateKey.publicKey?.count, 32, "Sources/Rattle/UpdateKey.swift must hold the 32-byte Ed25519 public key; run scripts/setup-update-signing.sh")
    }

    // MARK: the swap script

    private func runHelper(victim: Process) -> (swapped: Bool, victimGone: Bool, secs: Double) {
        let root = work.appendingPathComponent("helper-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin"), apps = root.appendingPathComponent("Apps"), w = root.appendingPathComponent("work")
        let newApp = w.appendingPathComponent("unpacked/Rattle.app")
        for d in [bin, apps.appendingPathComponent("Rattle.app/Contents"), newApp.appendingPathComponent("Contents")] { try! fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try! "old".write(to: apps.appendingPathComponent("Rattle.app/Contents/v"), atomically: true, encoding: .utf8)
        try! "new".write(to: newApp.appendingPathComponent("Contents/v"), atomically: true, encoding: .utf8)
        try! "#!/bin/sh\nexit 0\n".write(to: bin.appendingPathComponent("open"), atomically: true, encoding: .utf8)
        sh("/bin/chmod", ["+x", bin.appendingPathComponent("open").path])
        let script = w.appendingPathComponent("swap.sh")
        try! Updater.helperScript.write(to: script, atomically: true, encoding: .utf8)
        try! victim.run()
        let t0 = Date()
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path, String(victim.processIdentifier), apps.appendingPathComponent("Rattle.app").path, newApp.path, w.path]
        p.environment = ["PATH": bin.path + ":/usr/bin:/bin", "RATTLE_GRACE": "5"]
        try! p.run(); p.waitUntilExit()
        let installed = (try? String(contentsOf: apps.appendingPathComponent("Rattle.app/Contents/v"))) ?? ""
        return (installed == "new" && !fm.fileExists(atPath: w.path), !victim.isRunning, Date().timeIntervalSince(t0))
    }

    func testSwapScriptEndsAnAppThatWillNotQuit() {
        let stays = Process(); stays.executableURL = URL(fileURLWithPath: "/bin/sleep"); stays.arguments = ["300"]
        let r1 = runHelper(victim: stays)
        XCTAssertTrue(r1.swapped && r1.victimGone && r1.secs < 8, "\(r1)")
        let stubborn = Process(); stubborn.executableURL = URL(fileURLWithPath: "/bin/sh")
        stubborn.arguments = ["-c", "trap '' TERM; while true; do sleep 1; done"]
        let r2 = runHelper(victim: stubborn)
        XCTAssertTrue(r2.swapped && r2.victimGone && r2.secs < 12, "\(r2)")
        XCTAssertFalse(Updater.helperScript.contains("quarantine"))
    }

    // MARK: release notes

    func testReleaseNotesLoseLinksCreditsAndTheChangelogLine() {
        let gh = """
        ## What's Changed
        * Add search by @YashDayani in https://github.com/YashDayani/Rattle/pull/3
        * Fix [crash](https://github.com/a/b/issues/1) on open in https://github.com/a/b/pull/4
        ## New Contributors
        * @someone made their first contribution in https://github.com/a/b/pull/5

        **Full Changelog**: https://github.com/YashDayani/Rattle/compare/v1.1.1...v1.2.0
        """
        XCTAssertEqual(ReleaseNotes.parse(gh), [.bullet("Add search"), .bullet("Fix crash on open")])
        XCTAssertTrue(ReleaseNotes.parse("**Full Changelog**: https://github.com/a/b/compare/v1...v2").isEmpty)
        let ours = "## What's new\n\n### Add updates\n- Checks on every launch\n- Installs **in place**\n\n- A plain change\n\n**Full Changelog**: https://x"
        XCTAssertEqual(ReleaseNotes.parse(ours), [.heading("Add updates"), .bullet("Checks on every launch"), .bullet("Installs **in place**"), .bullet("A plain change")])
    }
}
