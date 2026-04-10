import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Detects Python installations on the system using filesystem inspection only.
/// Works within App Sandbox — no Process() calls needed.
enum PythonEnvironmentDetector {

    // MARK: - Models

    struct PythonInstallation: Identifiable, Sendable {
        let id = UUID()
        let path: String
        let version: String
        let major: Int
        let minor: Int
        let patch: Int
        let installMethod: InstallMethod
        let sitePackagesPath: String?
        let hasTorch: Bool
        let hasCoreMLTools: Bool
        let hasSciKitLearn: Bool
        let hasNumpy: Bool
        let hasScipy: Bool

        /// Human-readable summary line.
        var summary: String {
            var parts = ["Python \(version)", installMethod.rawValue]
            var pkgs: [String] = []
            if hasTorch { pkgs.append("torch") }
            if hasCoreMLTools { pkgs.append("coremltools") }
            if hasSciKitLearn { pkgs.append("sklearn") }
            if hasNumpy { pkgs.append("numpy") }
            if hasScipy { pkgs.append("scipy") }
            if pkgs.isEmpty {
                parts.append("no ML packages")
            } else {
                parts.append(pkgs.joined(separator: " + "))
            }
            return parts.joined(separator: " · ")
        }

        /// Whether all required ML packages are present.
        var hasAllMLPackages: Bool {
            hasTorch && hasCoreMLTools && hasSciKitLearn
        }

        /// Numeric score for ranking (higher = better).
        /// Prefers: ML packages installed > Homebrew > newer version.
        var score: Int {
            var s = 0
            // ML packages are the highest priority
            if hasTorch && hasCoreMLTools { s += 200000 }
            else if hasTorch || hasCoreMLTools { s += 100000 }
            if hasSciKitLearn { s += 50000 }
            // Homebrew is preferred — reliable pip, good package management
            if installMethod == .homebrew { s += 30000 }
            else if installMethod == .conda || installMethod == .miniforge { s += 20000 }
            else if installMethod == .pyenv { s += 15000 }
            // Version scoring: prefer newer Python (3.12+ all have good ML support now)
            if minor >= 12 { s += 5000 }
            else if minor == 11 { s += 3000 }
            s += minor * 100 + patch
            return s
        }

        /// Whether this installation uses Homebrew-managed Python.
        var isHomebrew: Bool { installMethod == .homebrew }
    }

    enum InstallMethod: String, Sendable {
        case homebrew = "Homebrew"
        case pythonOrg = "python.org"
        case xcodeCommandLineTools = "Xcode CLT"
        case conda = "Conda"
        case miniforge = "Miniforge"
        case pyenv = "pyenv"
        case unknown = "Unknown"
    }

    /// Information about the system's Homebrew installation.
    struct HomebrewInfo: Sendable {
        let brewPath: String
        let isAppleSilicon: Bool
        let cellarPath: String

        /// The Homebrew bin directory (e.g., /opt/homebrew/bin).
        var binPath: String {
            (brewPath as NSString).deletingLastPathComponent
        }
    }

    struct DetectionResult: Sendable {
        let installations: [PythonInstallation]
        let recommended: PythonInstallation?
        let warnings: [String]
        let recommendations: [String]
        let homebrew: HomebrewInfo?
    }

    // MARK: - Detection

    /// Scans all known Python installation paths and returns a ranked result.
    @MainActor
    static func detectAll() -> DetectionResult {
        let fm = FileManager.default
        #if os(macOS)
        let home = fm.homeDirectoryForCurrentUser.path
        #else
        let home = NSHomeDirectory()
        #endif

        // ── Candidate paths ──────────────────────────────────────────

        var candidates: [(path: String, method: InstallMethod)] = [
            // Xcode Command Line Tools / system
            ("/usr/bin/python3", .xcodeCommandLineTools),

            // Homebrew — Apple Silicon
            ("/opt/homebrew/bin/python3", .homebrew),
            ("/opt/homebrew/bin/python3.14", .homebrew),
            ("/opt/homebrew/bin/python3.13", .homebrew),
            ("/opt/homebrew/bin/python3.12", .homebrew),
            ("/opt/homebrew/bin/python3.11", .homebrew),
            ("/opt/homebrew/bin/python3.10", .homebrew),

            // Homebrew — Intel
            ("/usr/local/bin/python3", .homebrew),
            ("/usr/local/bin/python3.14", .homebrew),
            ("/usr/local/bin/python3.13", .homebrew),
            ("/usr/local/bin/python3.12", .homebrew),
            ("/usr/local/bin/python3.11", .homebrew),
            ("/usr/local/bin/python3.10", .homebrew),

            // python.org framework installer
            ("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3", .pythonOrg),
            ("/Library/Frameworks/Python.framework/Versions/3.13/bin/python3", .pythonOrg),
            ("/Library/Frameworks/Python.framework/Versions/3.12/bin/python3", .pythonOrg),
            ("/Library/Frameworks/Python.framework/Versions/3.11/bin/python3", .pythonOrg),
            ("/Library/Frameworks/Python.framework/Versions/3.10/bin/python3", .pythonOrg),

            // Conda / Miniconda / Miniforge
            ("/opt/anaconda3/bin/python3", .conda),
            ("/opt/miniconda3/bin/python3", .conda),
            ("\(home)/anaconda3/bin/python3", .conda),
            ("\(home)/miniconda3/bin/python3", .conda),
            ("\(home)/miniforge3/bin/python3", .miniforge),

            // pyenv shim (lowest priority — resolves to actual install)
            ("\(home)/.pyenv/shims/python3", .pyenv),
        ]

        // Scan pyenv versions directory
        let pyenvDir = "\(home)/.pyenv/versions"
        if let versions = try? fm.contentsOfDirectory(atPath: pyenvDir) {
            for ver in versions.sorted().reversed() {
                candidates.append(("\(pyenvDir)/\(ver)/bin/python3", .pyenv))
            }
        }

        // Scan Homebrew Cellar for explicit version installs
        for cellarBase in ["/opt/homebrew/Cellar", "/usr/local/Cellar"] {
            if let entries = try? fm.contentsOfDirectory(atPath: cellarBase) {
                for entry in entries where entry.hasPrefix("python@") {
                    let versionDir = "\(cellarBase)/\(entry)"
                    if let subs = try? fm.contentsOfDirectory(atPath: versionDir) {
                        for sub in subs.sorted().reversed() {
                            candidates.append(("\(cellarBase)/\(entry)/\(sub)/bin/python3", .homebrew))
                        }
                    }
                }
            }
        }

        // ── Inspect each candidate ──────────────────────────────────

        var installations: [PythonInstallation] = []
        var seenRealPaths: Set<String> = []

        for (candidatePath, method) in candidates {
            guard fm.fileExists(atPath: candidatePath) else { continue }

            let realPath = resolveSymlinks(candidatePath)
            guard !seenRealPaths.contains(realPath) else { continue }
            seenRealPaths.insert(realPath)

            let version = extractVersion(from: realPath, fallbackMethod: method)
            let (major, minor, patch) = parseVersion(version)

            // Require Python 3.10+
            guard major >= 3, minor >= 10 else { continue }

            // Detect install method from the resolved path (more accurate than candidate hint)
            let detectedMethod = detectInstallMethod(realPath: realPath, fallback: method)

            // Find ALL site-packages directories and check ML libraries across all of them.
            // Use both the resolved path AND the original candidate path for lookups,
            // since Homebrew pip installs to /opt/homebrew/lib/ not the Cellar path.
            let allSitePackages = findAllSitePackages(pythonPath: realPath, major: major, minor: minor)
            let candidateSitePackages = (realPath != candidatePath)
                ? findAllSitePackages(pythonPath: candidatePath, major: major, minor: minor)
                : []
            let allUserSitePackages = findAllUserSitePackages(home: home, major: major, minor: minor)
            let allPaths = Array(Set(allSitePackages + candidateSitePackages + allUserSitePackages))

            let hasTorch = checkPackageExists("torch", in: allPaths)
            let hasCoreMLTools = checkPackageExists("coremltools", in: allPaths)
            let hasSciKitLearn = checkPackageExists("sklearn", in: allPaths)
                || checkPackageExists("scikit-learn", in: allPaths)
                || checkPackageExists("scikit_learn", in: allPaths)
            let hasNumpy = checkPackageExists("numpy", in: allPaths)
            let hasScipy = checkPackageExists("scipy", in: allPaths)

            Instrumentation.log(
                "Python candidate inspected",
                area: .mlTraining, level: .info,
                details: "candidate=\(candidatePath) real=\(realPath) version=\(version) sitePackages=\(allPaths) torch=\(hasTorch) coremltools=\(hasCoreMLTools) sklearn=\(hasSciKitLearn) numpy=\(hasNumpy) scipy=\(hasScipy)"
            )

            installations.append(PythonInstallation(
                path: candidatePath,
                version: version,
                major: major,
                minor: minor,
                patch: patch,
                installMethod: detectedMethod,
                sitePackagesPath: allSitePackages.first ?? allUserSitePackages.first,
                hasTorch: hasTorch,
                hasCoreMLTools: hasCoreMLTools,
                hasSciKitLearn: hasSciKitLearn,
                hasNumpy: hasNumpy,
                hasScipy: hasScipy
            ))
        }

        // Sort by score (packages + version)
        installations.sort { $0.score > $1.score }

        // ── Warnings and recommendations ────────────────────────────

        var warnings: [String] = []
        var recommendations: [String] = []
        let recommended = installations.first

        // ── Detect Homebrew ──────────────────────────────────────────
        let homebrewInfo = detectHomebrew()

        if installations.isEmpty {
            warnings.append("No Python 3.10+ installation found on this system.")
            if homebrewInfo != nil {
                recommendations.append("Install via Homebrew:  brew install python@3.13")
            } else {
                recommendations.append("Install Homebrew first, then:  brew install python@3.13")
            }
        } else if let rec = recommended {
            if !rec.hasTorch {
                recommendations.append("Install PyTorch:  \(rec.path) -m pip install torch")
            }
            if !rec.hasCoreMLTools {
                recommendations.append("Install coremltools:  \(rec.path) -m pip install coremltools")
            }
            if !rec.hasSciKitLearn {
                recommendations.append("Install scikit-learn:  \(rec.path) -m pip install scikit-learn")
            }
            if rec.minor < 12 {
                recommendations.append("Consider upgrading to Python 3.12+ for best ML package compatibility.")
            }
            if installations.filter({ $0.hasTorch && $0.hasCoreMLTools }).isEmpty {
                warnings.append("No installation has both PyTorch and coremltools. Install both to enable PINN training.")
            }
        }

        Instrumentation.log(
            "Python detection complete",
            area: .mlTraining, level: .info,
            details: "found=\(installations.count) recommended=\(recommended?.path ?? "none") homebrew=\(homebrewInfo != nil)"
        )

        return DetectionResult(
            installations: installations,
            recommended: recommended,
            warnings: warnings,
            recommendations: recommendations,
            homebrew: homebrewInfo
        )
    }

    // MARK: - Homebrew Detection

    /// Detects Homebrew installation by checking known paths.
    /// Uses multiple strategies: brew binary, Homebrew directory structure, and Cellar existence.
    private static func detectHomebrew() -> HomebrewInfo? {
        let fm = FileManager.default

        // Strategy 1: Check for brew binary (standard check)
        // Strategy 2: Check for Homebrew directory structure (more reliable on Tahoe)
        let candidates: [(brewPath: String, prefix: String, isAS: Bool)] = [
            ("/opt/homebrew/bin/brew", "/opt/homebrew", true),
            ("/usr/local/bin/brew", "/usr/local", false)
        ]

        for (brewPath, prefix, isAS) in candidates {
            // Check brew binary exists (isExecutableFile or fileExists)
            let hasBrew = fm.isExecutableFile(atPath: brewPath) || fm.fileExists(atPath: brewPath)
            // Check for Homebrew directory structure (Cellar or opt directories)
            let hasCellar = fm.fileExists(atPath: "\(prefix)/Cellar")
            let hasOpt = fm.fileExists(atPath: "\(prefix)/opt")
            // Check for Homebrew-managed Python specifically
            let hasBrewPython = fm.fileExists(atPath: "\(prefix)/bin/python3")
                || fm.fileExists(atPath: "\(prefix)/bin/python3.13")
                || fm.fileExists(atPath: "\(prefix)/bin/python3.12")
                || fm.fileExists(atPath: "\(prefix)/bin/python3.14")

            if hasBrew || hasCellar || hasOpt || hasBrewPython {
                return HomebrewInfo(
                    brewPath: fm.fileExists(atPath: brewPath) ? brewPath : "\(prefix)/bin/brew",
                    isAppleSilicon: isAS,
                    cellarPath: "\(prefix)/Cellar"
                )
            }
        }
        return nil
    }

    // MARK: - Symlink Resolution

    private static func resolveSymlinks(_ path: String) -> String {
        let fm = FileManager.default
        var resolved = path
        for _ in 0..<10 {
            guard let target = try? fm.destinationOfSymbolicLink(atPath: resolved) else {
                break
            }
            if target.hasPrefix("/") {
                resolved = target
            } else {
                let dir = (resolved as NSString).deletingLastPathComponent
                resolved = (dir as NSString).appendingPathComponent(target)
            }
        }
        // Standardize path to remove ".." and "." components
        // e.g. /opt/homebrew/bin/../Cellar/... → /opt/homebrew/Cellar/...
        return URL(fileURLWithPath: resolved).standardized.path
    }

    // MARK: - Version Extraction

    private static func extractVersion(from realPath: String, fallbackMethod: InstallMethod) -> String {
        let components = realPath.split(separator: "/").map(String.init)

        // python.org: .../Python.framework/Versions/3.12/bin/python3
        if let idx = components.firstIndex(of: "Versions"), idx + 1 < components.count {
            let ver = components[idx + 1]
            if ver.hasPrefix("3.") { return ver }
        }

        // Homebrew Cellar: .../python@3.12/3.12.4/bin/python3
        for (i, comp) in components.enumerated() {
            if comp.hasPrefix("python@"), i + 1 < components.count {
                let cellarVersion = components[i + 1]
                if cellarVersion.contains(".") { return cellarVersion }
            }
        }

        // pyenv: .../versions/3.12.4/bin/python3
        if let idx = components.firstIndex(of: "versions"), idx + 1 < components.count {
            let ver = components[idx + 1]
            if ver.hasPrefix("3.") { return ver }
        }

        // Binary name: python3.12 → 3.12
        if let name = components.last, name.hasPrefix("python") {
            let suffix = name.replacingOccurrences(of: "python", with: "")
            if suffix.hasPrefix("3.") { return suffix }
        }

        // Probe adjacent lib directory for python3.X folder
        let binDir = (realPath as NSString).deletingLastPathComponent
        let prefixDir = (binDir as NSString).deletingLastPathComponent
        let libDir = "\(prefixDir)/lib"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: libDir) {
            let pythonDirs = entries.filter { $0.hasPrefix("python3.") }.sorted().reversed()
            if let first = pythonDirs.first {
                return first.replacingOccurrences(of: "python", with: "")
            }
        }

        return "3.x"
    }

    private static func parseVersion(_ version: String) -> (Int, Int, Int) {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        return (
            parts.count > 0 ? parts[0] : 3,
            parts.count > 1 ? parts[1] : 0,
            parts.count > 2 ? parts[2] : 0
        )
    }

    // MARK: - Install Method Detection

    private static func detectInstallMethod(realPath: String, fallback: InstallMethod) -> InstallMethod {
        if realPath.contains("/opt/homebrew/") || realPath.contains("/usr/local/Cellar/") || realPath.contains("/usr/local/opt/") {
            return .homebrew
        }
        if realPath.contains("Python.framework") {
            return .pythonOrg
        }
        if realPath.contains(".pyenv/") {
            return .pyenv
        }
        if realPath.contains("anaconda") || realPath.contains("miniconda") {
            return .conda
        }
        if realPath.contains("miniforge") {
            return .miniforge
        }
        if realPath == "/usr/bin/python3" || realPath.hasPrefix("/Library/Developer/CommandLineTools/") {
            return .xcodeCommandLineTools
        }
        return fallback
    }

    // MARK: - Site-Packages Discovery

    /// Returns ALL valid site-packages directories for a Python installation.
    /// Homebrew Python resolves to Cellar but pip installs to /opt/homebrew/lib/…,
    /// and Homebrew formulas like pytorch use libexec virtual environments.
    /// We must check all possible locations, not just the binary-relative one.
    private static func findAllSitePackages(pythonPath: String, major: Int, minor: Int) -> [String] {
        let fm = FileManager.default
        let shortVersion = "\(major).\(minor)"
        var results: [String] = []

        // Homebrew standard paths — check first since pip installs here
        let brewAS = "/opt/homebrew/lib/python\(shortVersion)/site-packages"
        if fm.fileExists(atPath: brewAS) { results.append(brewAS) }

        let brewIntel = "/usr/local/lib/python\(shortVersion)/site-packages"
        if fm.fileExists(atPath: brewIntel) && !results.contains(brewIntel) { results.append(brewIntel) }

        // Homebrew libexec virtual environments — formulas like pytorch, scikit-image
        // install their Python packages here instead of the standard site-packages.
        // Path: /opt/homebrew/opt/<formula>/libexec/lib/python3.X/site-packages/
        for optBase in ["/opt/homebrew/opt", "/usr/local/opt"] {
            let knownMLFormulas = ["pytorch", "scikit-learn", "scikit-image", "scipy", "numpy"]
            for formula in knownMLFormulas {
                let libexecSP = "\(optBase)/\(formula)/libexec/lib/python\(shortVersion)/site-packages"
                if fm.fileExists(atPath: libexecSP) && !results.contains(libexecSP) {
                    results.append(libexecSP)
                }
            }
            // Also scan all formulas in opt/ for libexec site-packages (catches future formulas)
            if let entries = try? fm.contentsOfDirectory(atPath: optBase) {
                for entry in entries {
                    let libexecSP = "\(optBase)/\(entry)/libexec/lib/python\(shortVersion)/site-packages"
                    if fm.fileExists(atPath: libexecSP) && !results.contains(libexecSP) {
                        results.append(libexecSP)
                    }
                }
            }
        }

        // Relative to the binary prefix (works for python.org, pyenv, conda)
        let binDir = (pythonPath as NSString).deletingLastPathComponent
        let prefixDir = (binDir as NSString).deletingLastPathComponent
        let path = "\(prefixDir)/lib/python\(shortVersion)/site-packages"
        if fm.fileExists(atPath: path) && !results.contains(path) { results.append(path) }

        // python.org framework
        let frameworkPath = "/Library/Frameworks/Python.framework/Versions/\(shortVersion)/lib/python\(shortVersion)/site-packages"
        if fm.fileExists(atPath: frameworkPath) && !results.contains(frameworkPath) { results.append(frameworkPath) }

        // Homebrew Cellar framework layout (resolved symlink):
        // .../Cellar/python@3.X/X.Y.Z/Frameworks/Python.framework/Versions/3.X/lib/python3.X/site-packages
        let resolvedPath = resolveSymlinks(pythonPath)
        if resolvedPath != pythonPath {
            let resolvedBinDir = (resolvedPath as NSString).deletingLastPathComponent
            let resolvedPrefixDir = (resolvedBinDir as NSString).deletingLastPathComponent
            let resolvedSP = "\(resolvedPrefixDir)/lib/python\(shortVersion)/site-packages"
            if fm.fileExists(atPath: resolvedSP) && !results.contains(resolvedSP) { results.append(resolvedSP) }
        }

        return results
    }

    /// Returns ALL valid user site-packages directories.
    private static func findAllUserSitePackages(home: String, major: Int, minor: Int) -> [String] {
        let fm = FileManager.default
        let shortVersion = "\(major).\(minor)"
        var results: [String] = []

        let path = "\(home)/Library/Python/\(shortVersion)/lib/python/site-packages"
        if fm.fileExists(atPath: path) { results.append(path) }
        // Some installations use a slightly different layout
        let altPath = "\(home)/Library/Python/\(shortVersion)/lib/site-packages"
        if fm.fileExists(atPath: altPath) && !results.contains(altPath) { results.append(altPath) }

        return results
    }

    /// Checks whether a package exists in any of the given site-packages directories.
    /// Checks multiple naming conventions: directory, dist-info, egg-info, and .egg-link.
    private static func checkPackageExists(_ packageName: String, in sitePackagesPaths: [String]) -> Bool {
        let fm = FileManager.default
        // Normalize: pip uses underscores in dist-info names (e.g. scikit_learn-1.5.dist-info)
        let normalized = packageName.replacingOccurrences(of: "-", with: "_")
        for sp in sitePackagesPaths {
            // 1. Package directory (e.g. torch/, sklearn/, coremltools/)
            if fm.fileExists(atPath: "\(sp)/\(packageName)") { return true }
            if normalized != packageName, fm.fileExists(atPath: "\(sp)/\(normalized)") { return true }
            // 2. Scan for dist-info, egg-info, or egg-link (avoids exact version matching)
            if let entries = try? fm.contentsOfDirectory(atPath: sp) {
                let lower = packageName.lowercased()
                let normalizedLower = normalized.lowercased()
                for entry in entries {
                    let entryLower = entry.lowercased()
                    // dist-info: torch-2.3.0.dist-info, scikit_learn-1.5.2.dist-info
                    if entryLower.hasSuffix(".dist-info") || entryLower.hasSuffix(".egg-info") {
                        let prefix = entryLower
                            .replacingOccurrences(of: ".dist-info", with: "")
                            .replacingOccurrences(of: ".egg-info", with: "")
                        if prefix.hasPrefix(lower + "-") || prefix.hasPrefix(normalizedLower + "-")
                            || prefix == lower || prefix == normalizedLower {
                            return true
                        }
                    }
                    // egg-link (editable installs)
                    if entryLower == "\(lower).egg-link" || entryLower == "\(normalizedLower).egg-link" {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - Package Installation

    /// All ML packages needed for PINN training, including dependencies.
    static let allMLPackages = [
        "torch",
        "coremltools",
        "numpy",
        "scipy",
        "scikit-learn"
    ]

    // MARK: - Terminal Script Execution

    /// Runs a bash script in Terminal.app, bypassing macOS Tahoe Gatekeeper restrictions.
    ///
    /// macOS Tahoe blocks:
    /// 1. `Process()` from executing Homebrew binaries ("Operation not permitted")
    /// 2. `.command` files from unsigned/debug apps (Gatekeeper "cannot verify" dialog)
    /// 3. `NSAppleScript` Apple Events (Automation consent prompt may not appear for debug builds)
    ///
    /// Strategy (in priority order):
    /// 1. **osascript**: Use `/usr/bin/osascript` (system binary) to tell Terminal.app to `do script`.
    /// 2. **Code-signed .command file**: Write a .command file, sign it with the developer's certificate
    ///    (discovered at runtime via `security find-identity`), and open it.
    /// 3. **Direct bash**: Run `/bin/bash -c` directly via Process() — no Terminal UI but guaranteed to work.
    #if os(macOS)
    @MainActor
    @discardableResult
    static func runScriptInTerminal(_ script: String, filename: String = "spf_script.command") -> Bool {
        // Strategy 1: osascript → Terminal "do script" (preferred — no file, no Gatekeeper)
        if runViaOsascript(script, label: filename) {
            return true
        }

        // Strategy 2: Code-signed .command file (satisfies Gatekeeper)
        Instrumentation.log(
            "osascript approach failed, trying code-signed .command file",
            area: .mlTraining, level: .info,
            details: "file=\(filename)"
        )
        if runViaSignedCommandFile(script, filename: filename) {
            return true
        }

        // Strategy 3: Direct bash execution (no Terminal UI, but works without Gatekeeper)
        Instrumentation.log(
            "Code-signed .command file failed, falling back to direct bash execution",
            area: .mlTraining, level: .info,
            details: "file=\(filename)"
        )
        return runViaDirectBash(script, label: filename)
    }

    /// Launches a bash script in Terminal.app via `/usr/bin/osascript` (AppleScript).
    /// Writes the script to a temp file first — avoids fragile AppleScript string escaping
    /// for multi-line bash scripts that contain quotes, $variables, emoji, and backslashes.
    /// `/usr/bin/osascript` is a system binary that Process() can always execute, even on Tahoe.
    private static func runViaOsascript(_ script: String, label: String) -> Bool {
        let fm = FileManager.default
        let safeName = label
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let scriptURL = fm.temporaryDirectory
            .appendingPathComponent("spf_\(safeName)_\(ProcessInfo.processInfo.processIdentifier).sh")

        // Step 1: Write script to temp file (avoids AppleScript string escaping issues)
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            Instrumentation.log(
                "Failed to write temp script for osascript",
                area: .mlTraining, level: .warning,
                details: "label=\(label) error=\(error.localizedDescription)"
            )
            return false
        }

        // Step 2: Remove quarantine and code-sign the temp script
        scriptURL.path.withCString { cPath in
            _ = removexattr(cPath, "com.apple.quarantine", 0)
        }
        codesignFile(at: scriptURL.path)

        // Step 3: Tell Terminal to run the script file via AppleScript.
        // Using AppleScript's "quoted form of" for safe shell path escaping.
        let posixPath = scriptURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScriptSource = """
        set spfScript to "\(posixPath)"
        tell application "Terminal"
            activate
            do script "/bin/bash " & quoted form of spfScript
        end tell
        """

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScriptSource]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            let exitCode = process.terminationStatus
            if exitCode == 0 {
                Instrumentation.log(
                    "Script launched in Terminal via osascript (file-based)",
                    area: .mlTraining, level: .info,
                    details: "label=\(label) scriptFile=\(scriptURL.path)"
                )
                return true
            } else {
                Instrumentation.log(
                    "osascript exited with non-zero code",
                    area: .mlTraining, level: .warning,
                    details: "label=\(label) exitCode=\(exitCode) — may need Automation permission in System Settings → Privacy → Automation"
                )
                return false
            }
        } catch {
            Instrumentation.log(
                "osascript launch failed",
                area: .mlTraining, level: .warning,
                details: "label=\(label) error=\(error.localizedDescription)"
            )
            return false
        }
    }

    // MARK: - Code-Signing Identity Discovery

    /// Cached signing identity (discovered once per session).
    private static var _cachedSigningIdentity: String?
    private static var _identityLookupDone = false

    /// Finds the first available code-signing identity from the user's keychain.
    /// Runs `security find-identity -v -p codesigning` and parses the output.
    private static func findSigningIdentity() -> String? {
        if _identityLookupDone { return _cachedSigningIdentity }
        _identityLookupDone = true

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-identity", "-v", "-p", "codesigning"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            // Parse lines like:
            //   1) ABC123... "Apple Development: Name (TEAM)"
            //   2) DEF456... "Developer ID Application: Name (TEAM)"
            // Prefer "Apple Development" or "Developer ID Application"
            let lines = output.components(separatedBy: "\n")
            var bestIdentity: String?

            for line in lines {
                // Extract the quoted identity name
                guard let quoteStart = line.firstIndex(of: "\""),
                      let quoteEnd = line[line.index(after: quoteStart)...].firstIndex(of: "\"") else { continue }
                let identity = String(line[line.index(after: quoteStart)..<quoteEnd])

                // Prefer Developer ID (most trusted) → Apple Development → any valid identity
                if identity.hasPrefix("Developer ID Application") {
                    _cachedSigningIdentity = identity
                    Instrumentation.log(
                        "Found Developer ID signing identity",
                        area: .mlTraining, level: .info,
                        details: "identity=\(identity)"
                    )
                    return identity
                }
                if identity.hasPrefix("Apple Development") && bestIdentity == nil {
                    bestIdentity = identity
                }
                if bestIdentity == nil && !identity.isEmpty {
                    bestIdentity = identity
                }
            }

            _cachedSigningIdentity = bestIdentity
            if let id = bestIdentity {
                Instrumentation.log(
                    "Found signing identity",
                    area: .mlTraining, level: .info,
                    details: "identity=\(id)"
                )
            } else {
                Instrumentation.log(
                    "No code-signing identity found in keychain",
                    area: .mlTraining, level: .warning,
                    details: ""
                )
            }
            return bestIdentity
        } catch {
            Instrumentation.log(
                "Failed to query signing identities",
                area: .mlTraining, level: .warning,
                details: "error=\(error.localizedDescription)"
            )
            return nil
        }
    }

    /// Code-signs a file at the given path using the developer's certificate.
    /// Falls back to ad-hoc signing (`-`) if no identity is found.
    @discardableResult
    static func codesignFile(at path: String) -> Bool {
        let identity = findSigningIdentity() ?? "-"

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = [
                "--force",
                "--sign", identity,
                path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            let success = process.terminationStatus == 0
            Instrumentation.log(
                success ? "Code-signed script file" : "codesign failed",
                area: .mlTraining, level: success ? .info : .warning,
                details: "file=\(path) identity=\(identity) exitCode=\(process.terminationStatus)"
            )
            return success
        } catch {
            Instrumentation.log(
                "codesign process launch failed",
                area: .mlTraining, level: .warning,
                details: "file=\(path) error=\(error.localizedDescription)"
            )
            return false
        }
    }

    /// Writes a .command file, code-signs it with the developer's certificate,
    /// removes quarantine, and opens it via NSWorkspace.
    private static func runViaSignedCommandFile(_ script: String, filename: String) -> Bool {
        // Write to Application Support (less likely to be quarantined than /tmp)
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let scriptsDir = appSupportDir
            .appendingPathComponent("com.zincoverde.SPFSpectralAnalyzer", isDirectory: true)
            .appendingPathComponent("TempScripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)

        let commandFilename = filename.hasSuffix(".command") ? filename : filename.replacingOccurrences(of: ".sh", with: ".command")
        let scriptURL = scriptsDir.appendingPathComponent(commandFilename)
        let path = scriptURL.path

        // Step 1: Write the script file
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: path
            )
        } catch {
            Instrumentation.log(
                "Failed to write Terminal script",
                area: .mlTraining, level: .error,
                details: "file=\(commandFilename) error=\(error.localizedDescription)"
            )
            return false
        }

        // Step 2: Remove quarantine via C removexattr()
        path.withCString { cPath in
            _ = removexattr(cPath, "com.apple.quarantine", 0)
        }

        // Step 3: Code-sign the .command file with the developer's certificate
        codesignFile(at: path)

        // Step 4: Open the .command file via NSWorkspace
        NSWorkspace.shared.open(scriptURL)

        Instrumentation.log(
            "Script launched in Terminal via code-signed .command file",
            area: .mlTraining, level: .info,
            details: "file=\(commandFilename) path=\(path)"
        )
        return true
    }

    /// Last resort: runs the script directly via /bin/bash.
    /// No Terminal window — output goes to the app's stdout/stderr.
    /// Still useful because the ML training manager reads process output via pipes.
    private static func runViaDirectBash(_ script: String, label: String) -> Bool {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script]
            // Inherit PATH so Homebrew/pyenv binaries are found
            var env = ProcessInfo.processInfo.environment
            let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            let currentPath = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
            process.environment = env
            try process.run()

            Instrumentation.log(
                "Script launched via direct /bin/bash",
                area: .mlTraining, level: .info,
                details: "label=\(label) pid=\(process.processIdentifier)"
            )
            return true
        } catch {
            Instrumentation.log(
                "Direct bash execution failed",
                area: .mlTraining, level: .error,
                details: "label=\(label) error=\(error.localizedDescription)"
            )
            return false
        }
    }

    /// Opens a Terminal window that installs or upgrades Python via Homebrew.
    @MainActor
    static func installPythonViaBrew() {
        let brewPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew")
            ? "/opt/homebrew/bin/brew"
            : "/usr/local/bin/brew"

        let script = """
        #!/bin/bash
        clear
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║   SPF Spectral Analyzer — Python Installer (Homebrew)   ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""

        # Check if Homebrew exists
        if ! command -v \(brewPath) &> /dev/null; then
            echo "  Homebrew not found. Installing Homebrew first..."
            echo ""
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            echo ""
        fi

        echo "→ Updating Homebrew..."
        \(brewPath) update 2>&1
        echo ""

        echo "→ Installing/upgrading Python..."
        \(brewPath) install python 2>&1 || \(brewPath) upgrade python 2>&1
        echo ""

        echo "→ Installing ML packages..."
        PYTHON_PATH="$(\(brewPath) --prefix python)/bin/python3"
        if [ ! -f "$PYTHON_PATH" ]; then
            PYTHON_PATH="$(\(brewPath) --prefix)/bin/python3"
        fi
        echo "  Using: $PYTHON_PATH"
        echo ""
        PIP_BREAK_SYSTEM_PACKAGES=1 "$PYTHON_PATH" -m pip install --upgrade pip torch coremltools numpy scipy scikit-learn 2>&1

        STATUS=$?
        echo ""
        echo "────────────────────────────────────────────────────────────"
        echo ""
        if [ $STATUS -eq 0 ]; then
            echo "  ✅  Python + ML packages installed successfully!"
            echo ""
            echo "  Python location: $PYTHON_PATH"
            "$PYTHON_PATH" --version
        else
            echo "  ❌  Installation encountered errors (exit code: $STATUS)"
        fi
        echo ""
        echo "  Return to Settings → ML Training → Detect & Setup"
        echo ""
        echo "  Press any key to close this window..."
        read -n 1 -s
        exit 0
        """

        runScriptInTerminal(script, filename: "spf_python_install.command")
    }
    #endif
}

// MARK: - Package Installer (Terminal-based for macOS Tahoe compatibility)

/// Installs ML packages by running a bash script in Terminal.app.
/// Uses `osascript` to inject the script directly into Terminal (preferred),
/// falling back to a `.command` file if automation permission is denied.
/// The user sees installation progress in Terminal, then clicks
/// "Detect & Setup" in the app to verify.
#if os(macOS)
@MainActor @Observable
final class PackageInstaller {

    enum Status: Sendable {
        case idle
        case waitingForTerminal
        case succeeded
        case failed(message: String)

        var isIdle: Bool {
            if case .idle = self { return true }
            return false
        }
    }

    /// Which install method to use for ML packages.
    enum InstallMethod: String, CaseIterable, Sendable {
        case homebrew = "Homebrew"
        case pip = "pip"

        var description: String {
            switch self {
            case .homebrew: return "brew install (recommended for Homebrew-managed Python)"
            case .pip: return "pip install (works with any Python)"
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var activeMethod: InstallMethod = .pip

    var isInstalling: Bool {
        if case .waitingForTerminal = status { return true }
        return false
    }

    /// Detects the best install method for this system.
    static func detectInstallMethod() -> InstallMethod {
        let fm = FileManager.default
        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for path in brewPaths {
            if fm.fileExists(atPath: path) { return .homebrew }
        }
        if fm.fileExists(atPath: "/opt/homebrew/Cellar")
            || fm.fileExists(atPath: "/usr/local/Cellar") {
            return .homebrew
        }
        return .pip
    }

    /// Opens Terminal to install ML packages via Homebrew + pip or pip-only.
    /// Uses osascript → Terminal to run a bash script, avoiding Gatekeeper.
    func installPackages(_ packages: [String], pythonPath: String, method: InstallMethod? = nil) {
        let installMethod = method ?? Self.detectInstallMethod()
        activeMethod = installMethod
        status = .waitingForTerminal

        let brewPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew")
            ? "/opt/homebrew/bin/brew"
            : "/usr/local/bin/brew"

        let pipPackageList = packages.joined(separator: " ")

        let script: String
        if installMethod == .homebrew {
            // Map torch → pytorch formula name for Homebrew
            let brewFormulas = packages.compactMap { pkg -> String? in
                switch pkg {
                case "torch": return "pytorch"
                case "numpy": return "numpy"
                case "scipy": return "scipy"
                default: return nil
                }
            }
            let pipOnlyPkgs = packages.filter { !["torch", "numpy", "scipy"].contains($0) }

            script = """
            #!/bin/bash
            clear
            echo ""
            echo "╔══════════════════════════════════════════════════════════╗"
            echo "║  SPF Spectral Analyzer — ML Package Installer           ║"
            echo "╚══════════════════════════════════════════════════════════╝"
            echo ""
            echo "  Method:  Homebrew + pip"
            echo "  Python:  \(pythonPath)"
            echo ""
            echo "────────────────────────────────────────────────────────────"
            echo ""

            # Step 1: Homebrew packages (pytorch, numpy, scipy)
            \(brewFormulas.isEmpty ? "# No Homebrew formulas needed" : """
            echo "→ Step 1: Installing Homebrew packages: \(brewFormulas.joined(separator: ", "))..."
            echo ""
            \(brewPath) install \(brewFormulas.joined(separator: " ")) 2>&1 || \(brewPath) upgrade \(brewFormulas.joined(separator: " ")) 2>&1
            echo ""
            """)

            # Step 2: pip packages (coremltools, scikit-learn, and any others)
            \(pipOnlyPkgs.isEmpty ? "# No pip-only packages needed" : """
            echo "→ Step 2: Installing pip packages: \(pipOnlyPkgs.joined(separator: ", "))..."
            echo ""
            PIP_BREAK_SYSTEM_PACKAGES=1 "\(pythonPath)" -m pip install --upgrade \(pipOnlyPkgs.joined(separator: " ")) 2>&1
            echo ""
            """)

            STATUS=$?
            echo ""
            echo "────────────────────────────────────────────────────────────"
            echo ""
            if [ $STATUS -eq 0 ]; then
                echo "  ✅  ML packages installed successfully!"
            else
                echo "  ⚠️  Some packages may have had issues (exit code: $STATUS)"
                echo "      Check the output above for details."
            fi
            echo ""
            echo "  → Return to the app: Settings → ML Training → Detect & Setup"
            echo ""
            echo "  Press any key to close this window..."
            read -n 1 -s
            exit 0
            """
        } else {
            script = """
            #!/bin/bash
            clear
            echo ""
            echo "╔══════════════════════════════════════════════════════════╗"
            echo "║  SPF Spectral Analyzer — ML Package Installer           ║"
            echo "╚══════════════════════════════════════════════════════════╝"
            echo ""
            echo "  Method:  pip install"
            echo "  Python:  \(pythonPath)"
            echo ""
            echo "────────────────────────────────────────────────────────────"
            echo ""

            echo "→ Upgrading pip..."
            PIP_BREAK_SYSTEM_PACKAGES=1 "\(pythonPath)" -m pip install --upgrade pip 2>&1
            echo ""

            echo "→ Installing ML packages: \(pipPackageList)..."
            echo "  (this may take several minutes for large packages like PyTorch)"
            echo ""
            PIP_BREAK_SYSTEM_PACKAGES=1 "\(pythonPath)" -m pip install --upgrade \(pipPackageList) 2>&1

            STATUS=$?
            echo ""
            echo "────────────────────────────────────────────────────────────"
            echo ""
            if [ $STATUS -eq 0 ]; then
                echo "  ✅  ML packages installed successfully!"
            else
                echo "  ⚠️  Some packages may have had issues (exit code: $STATUS)"
                echo "      Check the output above for details."
            fi
            echo ""
            echo "  → Return to the app: Settings → ML Training → Detect & Setup"
            echo ""
            echo "  Press any key to close this window..."
            read -n 1 -s
            exit 0
            """
        }

        // Launch via NSAppleScript → Terminal (bypasses Gatekeeper)
        let success = PythonEnvironmentDetector.runScriptInTerminal(
            script, filename: "spf_ml_install.command"
        )

        if success {
            status = .waitingForTerminal
            Instrumentation.log(
                "Opened ML package installer in Terminal",
                area: .mlTraining, level: .info,
                details: "method=\(installMethod.rawValue) python=\(pythonPath) packages=\(pipPackageList)"
            )
        } else {
            status = .failed(message: "Could not open Terminal. Check System Settings → Privacy → Automation.")
            Instrumentation.log(
                "Failed to launch ML installer in Terminal",
                area: .mlTraining, level: .error,
                details: "method=\(installMethod.rawValue)"
            )
        }
    }

    /// Resets the installer to idle state.
    func reset() {
        status = .idle
    }
}
#endif
