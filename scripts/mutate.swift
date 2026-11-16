import Darwin
import Foundation

setbuf(stdout, nil)

private let supportedPackages = ["DenDomain", "DenIPCProtocol", "DenInfrastructure", "DenApplication", "DenModels"]
private let packagePattern = #"^Packages/("# + supportedPackages.joined(separator: "|") + #")/Sources/.*\.swift$"#
private let skipPattern =
    #"Logger|os_log|PerformanceTrace|print\(|debugDescription|#Preview|\.sorted\s*(?:\(\s*by:\s*)?\{"#
private let astGrepRulesYAML = """
    id: binary-op
    language: Swift
    rule:
      all:
        - any: [
            {kind: equality_expression}, {kind: comparison_expression},
            {kind: conjunction_expression}, {kind: disjunction_expression},
            {kind: infix_expression},
          ]
        - has: {field: lhs, pattern: $LHS}
        - has: {field: rhs, pattern: $RHS}
    ---
    id: prefix-bang
    language: Swift
    rule: {kind: bang, inside: {kind: prefix_expression}}
    ---
    id: return-bool
    language: Swift
    rule: {kind: boolean_literal, inside: {kind: control_transfer_statement}}
    """
private let operatorSwaps = [
    "==": "!=", "!=": "==", "&&": "||", "||": "&&", "<=": "<", "<": "<=", ">=": ">", ">": ">=",
]
private let repoRootURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    func withLock<Result>(_ body: (inout Value) -> Result) -> Result { lock.withLock { body(&stored) } }
}

private struct Mutant {
    let file: String
    let line: Int
    let text: String
    let start: Int
    let end: Int
    let orig: String
    let swap: String
    var label: String { "\(file):\(line) (\(orig) -> \(swap.isEmpty ? "(removed)" : swap))" }
}

private let stateBox = LockedBox<(active: (String, Data)?, proc: Process?, sources: [DispatchSourceSignal])>(
    (nil, nil, [])
)

private func decodeUTF8<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
    String(bytes: bytes, encoding: .utf8) ?? ""
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

private func restoreActiveFile(exitCode: Int32? = nil) {
    stateBox.withLock { state in
        state.proc?.terminate()
        state.proc = nil
        if let (path, data) = state.active {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            state.active = nil
        }
        if let exitCode { _exit(exitCode) }
    }
}

private func installSignalHandlers() {
    for (sig, code) in [(SIGINT, Int32(130)), (SIGTERM, Int32(143))] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .global(qos: .userInitiated))
        src.setEventHandler { restoreActiveFile(exitCode: code) }
        src.resume()
        stateBox.withLock { $0.sources.append(src) }
    }
}

private func readPipe(_ pipe: Pipe, group: DispatchGroup) -> LockedBox<Data> {
    let box = LockedBox(Data())
    group.enter()
    DispatchQueue.global().async {
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        box.withLock { $0 = data }
        group.leave()
    }
    return box
}

private func run(_ cmd: String, _ args: [String], env: [String: String] = [:]) throws -> (
    code: Int32, out: String, all: String
) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = [cmd] + args
    proc.currentDirectoryURL = repoRootURL
    if !env.isEmpty { proc.environment = ProcessInfo.processInfo.environment.merging(env) { _, added in added } }

    let outPipe = Pipe()
    let errPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = errPipe
    try proc.run()
    stateBox.withLock { $0.proc = proc }

    let group = DispatchGroup()
    let outBox = readPipe(outPipe, group: group)
    let errBox = readPipe(errPipe, group: group)
    proc.waitUntilExit()
    group.wait()
    stateBox.withLock { $0.proc = nil }

    let out = outBox.withLock { decodeUTF8($0) }
    let err = errBox.withLock { decodeUTF8($0) }
    return (proc.terminationStatus, out, [out, err].filter { !$0.isEmpty }.joined(separator: "\n"))
}

private func isSupportedPath(_ path: String) -> Bool {
    path.range(of: packagePattern, options: .regularExpression) != nil
}

private func resolveTargets(_ targetArgs: [String]) -> [String] {
    let fileManager = FileManager.default
    let root = repoRootURL.path.hasSuffix("/") ? repoRootURL.path : repoRootURL.path + "/"
    let relPath: (URL) -> String = { url in
        let path = url.standardizedFileURL.path
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
    }

    var collected: [String] = []
    for arg in targetArgs {
        let resolved = URL(fileURLWithPath: arg, relativeTo: repoRootURL).standardizedFileURL
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDir) else {
            fail("Target path not found: \(arg)")
        }
        if !isDir.boolValue {
            let rel = relPath(resolved)
            guard isSupportedPath(rel) else {
                let expected = supportedPackages.joined(separator: ",")
                fail("Unsupported target file (expected Packages/{\(expected)}/Sources/**/*.swift): \(arg)")
            }
            collected.append(rel)
            continue
        }
        let prevCount = collected.count
        let enumerator = fileManager.enumerator(
            at: resolved,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let rel = relPath(fileURL)
            if isSupportedPath(rel) { collected.append(rel) }
        }
        guard collected.count > prevCount else { fail("No supported Swift source files found under directory: \(arg)") }
    }
    return Array(Set(collected)).sorted()
}

private func parseDiffChangedLines(_ diffOutput: String) -> [String: Set<Int>] {
    var changed: [String: Set<Int>] = [:]
    var currentFile: String?
    for line in diffOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
        if line.hasPrefix("+++ b/") {
            let path = String(line.dropFirst(6))
            currentFile = isSupportedPath(path) ? path : nil
        } else if line.hasPrefix("+++ ") {
            currentFile = nil
        } else if line.hasPrefix("@@ "), let file = currentFile {
            let plusToken = line.split(separator: " ").dropFirst(2).first ?? ""
            guard plusToken.hasPrefix("+") else { continue }
            let nums = plusToken.dropFirst().split(separator: ",", maxSplits: 1)
            guard let start = nums.first.flatMap({ Int($0) }) else { continue }
            let count = nums.count > 1 ? (Int(nums[1]) ?? 1) : 1
            if count > 0 { changed[file, default: []].formUnion(start..<(start + count)) }
        }
    }
    return changed
}

private func byteRange(in obj: Any?) -> (Int, Int)? {
    guard let map = obj as? [String: Any],
        let offsets = (map["range"] as? [String: Any])?["byteOffset"] as? [String: Any],
        let start = offsets["start"] as? Int,
        let end = offsets["end"] as? Int
    else { return nil }
    return (start, end)
}

private func lineInfo(in bytes: [UInt8], byteOffset: Int) -> (Int, String) {
    let offset = min(max(0, byteOffset), bytes.count)
    let line = bytes[..<offset].reduce(1) { $1 == 0x0A ? $0 + 1 : $0 }
    var start = offset
    while start > 0 && bytes[start - 1] != 0x0A { start -= 1 }
    var end = offset
    while end < bytes.count && bytes[end] != 0x0A && bytes[end] != 0x0D { end += 1 }
    return (line, decodeUTF8(bytes[start..<end]).trimmingCharacters(in: .whitespaces))
}

private func buildMutant(_ match: [String: Any], file: String, bytes: [UInt8]) -> Mutant? {
    guard let ruleId = match["ruleId"] as? String, var (start, end) = byteRange(in: match) else { return nil }
    let spaces: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
    var orig = ""
    var swap = ""

    switch ruleId {
    case "binary-op":
        let single = (match["metaVariables"] as? [String: Any])?["single"] as? [String: Any]
        guard let lhs = byteRange(in: single?["LHS"]), let rhs = byteRange(in: single?["RHS"]) else { return nil }
        (start, end) = (lhs.1, rhs.0)
        guard start >= 0, end <= bytes.count else { return nil }
        while start < end && spaces.contains(bytes[start]) { start += 1 }
        while end > start && spaces.contains(bytes[end - 1]) { end -= 1 }
        guard start < end else { return nil }
        orig = decodeUTF8(bytes[start..<end])
        guard let mapped = operatorSwaps[orig] else { return nil }
        swap = mapped
    case "prefix-bang":
        guard start >= 0, start < end, end <= bytes.count, decodeUTF8(bytes[start..<end]) == "!" else { return nil }
        orig = "!"
    case "return-bool":
        guard start >= 0, start < end, end <= bytes.count else { return nil }
        orig = decodeUTF8(bytes[start..<end])
        guard orig == "true" || orig == "false" else { return nil }
        swap = orig == "true" ? "false" : "true"
    default:
        return nil
    }

    let (line, lineText) = lineInfo(in: bytes, byteOffset: start)
    guard lineText.range(of: skipPattern, options: .regularExpression) == nil else { return nil }
    return Mutant(file: file, line: line, text: lineText, start: start, end: end, orig: orig, swap: swap)
}

private func discoverMutants(in files: [String], changedLines: [String: Set<Int>]?) throws -> [Mutant] {
    let args = ["scan", "--inline-rules", astGrepRulesYAML, "--json=compact"] + files
    let res = try run("ast-grep", args, env: ["COLORFGBG": "15;0"])
    guard res.code == 0 else { fail("ast-grep failed: \(res.all)") }
    let trimmed = res.out.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    guard let matches = try JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [[String: Any]] else {
        fail("ast-grep failed: unexpected JSON output")
    }

    var cache: [String: [UInt8]] = [:]
    var seen: Set<String> = []
    var mutants: [Mutant] = []
    for match in matches {
        guard let file = match["file"] as? String else { continue }
        if cache[file] == nil { cache[file] = try Array(Data(contentsOf: repoRootURL.appendingPathComponent(file))) }
        guard let bytes = cache[file], let mut = buildMutant(match, file: file, bytes: bytes) else { continue }
        if let allowed = changedLines, allowed[mut.file]?.contains(mut.line) != true { continue }
        if seen.insert("\(mut.file):\(mut.start):\(mut.end)").inserted { mutants.append(mut) }
    }
    return mutants.sorted { ($0.file, $0.start, $0.orig) < ($1.file, $1.start, $1.orig) }
}

private func testPackages(for file: String) -> [String] {
    let parts = file.split(separator: "/")
    guard parts.count >= 2 else { return [] }
    let pkg = String(parts[1])
    guard pkg == "DenApplication" else { return ["Packages/\(pkg)"] }

    let base = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
    let hasPkgTest: (String) -> Bool = { name in
        let path = "Packages/\(name)/Tests/\(name)Tests/\(base)Tests.swift"
        return FileManager.default.fileExists(atPath: repoRootURL.appendingPathComponent(path).path)
    }
    let (hasApp, hasModels) = (hasPkgTest("DenApplication"), hasPkgTest("DenModels"))
    if hasModels && !hasApp { return ["Packages/DenModels"] }
    if hasApp && !hasModels { return ["Packages/DenApplication"] }
    return ["Packages/DenApplication", "Packages/DenModels"]
}

private func evaluateMutant(_ mutant: Mutant) throws -> (tag: String, note: String) {
    let fileURL = repoRootURL.appendingPathComponent(mutant.file)
    let originalData = try Data(contentsOf: fileURL)
    let mutatedData = originalData[..<mutant.start] + Data(mutant.swap.utf8) + originalData[mutant.end...]
    stateBox.withLock { $0.active = (fileURL.path, originalData) }
    defer { restoreActiveFile() }
    try Data(mutatedData).write(to: fileURL, options: .atomic)

    for pkg in testPackages(for: mutant.file) {
        let res = try run("swift", ["test", "--package-path", pkg])
        if res.code == 0 { continue }
        let ran = res.all.contains("Test run started") || res.all.contains("✘ Test") || res.all.contains("Executed ")
        return ran ? ("KILLED  ", "") : ("SKIPPED ", " (compile error in \(pkg))")
    }
    return ("SURVIVED", "")
}

private func main() throws {
    installSignalHandlers()
    let args = Array(CommandLine.arguments.dropFirst())
    let strictMode = args.contains("--strict")
    let targetArgs = args.filter { $0 != "--strict" }
    let isDiffMode = targetArgs.isEmpty

    var targetFiles: [String] = []
    var changedLines: [String: Set<Int>]?
    if isDiffMode {
        var diffText = try run("git", ["diff", "HEAD", "--unified=0", "--", "Packages/*/Sources"]).out
        if diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let branch = try run("git", ["diff", "main...HEAD", "--unified=0", "--", "Packages/*/Sources"])
            if branch.code == 0 { diffText = branch.out }
        }
        let parsed = parseDiffChangedLines(diffText)
        changedLines = parsed
        targetFiles = parsed.keys.sorted()
    } else {
        targetFiles = resolveTargets(targetArgs)
    }

    let mutants = targetFiles.isEmpty ? [] : try discoverMutants(in: targetFiles, changedLines: changedLines)
    guard !mutants.isEmpty else {
        let emptyMsg =
            isDiffMode
            ? "✓ No mutable Swift lines in package diff."
            : "✓ No high-risk mutations discovered in target path(s)."
        print(emptyMsg)
        exit(0)
    }

    let mappedPackages = Array(Set(mutants.flatMap { testPackages(for: $0.file) })).sorted()
    print("Warming baseline test packages: \(mappedPackages.joined(separator: ", "))")
    for pkg in mappedPackages {
        let baseline = try run("swift", ["test", "--package-path", pkg])
        if baseline.code != 0 { fail("✗ Baseline tests failed in \(pkg) before mutation:\n\(baseline.all)") }
    }

    print("Running \(mutants.count) mutation(s) across \(Set(mutants.map(\.file)).count) file(s)...")
    var killedCount = 0
    var skippedCount = 0
    var survived: [Mutant] = []

    for (idx, mutant) in mutants.enumerated() {
        let (tag, note) = try evaluateMutant(mutant)
        print("[\(idx + 1)/\(mutants.count)] \(tag)  \(mutant.label)\(note)")
        if !note.isEmpty {
            skippedCount += 1
        } else if tag == "KILLED  " {
            killedCount += 1
        } else {
            survived.append(mutant)
        }
    }

    let evaluated = killedCount + survived.count
    let rate = evaluated > 0 ? (Double(killedCount) / Double(evaluated)) * 100.0 : 0.0
    let rateText = String(format: "%.1f", rate)
    print(
        "\nMutation summary: Killed \(killedCount) / \(evaluated) (\(rateText)%) | Survived: \(survived.count) | Skipped (compile): \(skippedCount)"
    )
    if !survived.isEmpty {
        print("\nSurvived mutants:")
        for mutant in survived { print("  - \(mutant.label) | \(mutant.text)") }
    }
    if strictMode && !survived.isEmpty { exit(1) }
}

do { try main() } catch {
    restoreActiveFile()
    fail("Error: \(error)")
}
