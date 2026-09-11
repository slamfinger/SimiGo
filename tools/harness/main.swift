// SimiGo 协议层回归骨架（持久版）
// 用法:
//   harness normal|cancel|disconnect|cancel_requeue   自带 stub 服务，自包含回归
//   harness p0                                        P0 验收矩阵（客户端模式，需真实 app 运行于 :8000）
// 编译: ~/.simigo/harness/build.sh（源码取自工作区，含未提交改动）

import Foundation
import Network

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let appPort: UInt16 = 8000
let tracePath = NSHomeDirectory() + "/.simigo/logs/native_mlx_trace.log"

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled: [String] = []
    func recordCancel(_ id: String) {
        lock.lock(); _cancelled.append(id); lock.unlock()
        print("[HARNESS] >>> cancelGenerationHandler fired: \(id)")
    }
    var cancelled: [String] {
        lock.lock(); defer { lock.unlock() }; return _cancelled
    }
}
let recorder = Recorder()

let watchdogSeconds: Double = mode == "p0" ? 900 : 60
DispatchQueue.global().asyncAfter(deadline: .now() + watchdogSeconds) {
    print("[HARNESS] GLOBAL TIMEOUT"); exit(3)
}

let slowMode = Locked(false)

let stubGenerate: HTTPServer.GenerateHandler = { _, _, _, _, _, _, _, onChunk, _ in
    let chunks = slowMode.value ? 60 : 8
    let interval: UInt64 = slowMode.value ? 100_000_000 : 50_000_000
    for i in 0..<chunks {
        if Task.isCancelled { throw CancellationError() }
        onChunk("tok\(i) ")
        if mode == "cancel" && i == 1 {
            throw CancellationError()
        }
        try await Task.sleep(nanoseconds: interval)
    }
    return "done"
}

let port: UInt16 = 23000 + UInt16.random(in: 0..<20000)
let server = HTTPServer(
    port: Int(port),
    modelId: "regression",
    bindHost: "127.0.0.1",
    bonjourEnabled: false,
    generateHandler: stubGenerate,
    checkHealthHandler: { true },
    cancelGenerationHandler: { recorder.recordCancel($0) }
)
if mode != "p0" {
    try server.start()
    Thread.sleep(forTimeInterval: 0.3)
}

// MARK: - POSIX client

func makeSocket(lingerRST: Bool) throws -> Int32 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }
    var nosigpipe: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
    if lingerRST {
        var ling = linger(l_onoff: 1, l_linger: 0)
        setsockopt(fd, SOL_SOCKET, SO_LINGER, &ling, socklen_t(MemoryLayout<linger>.size))
    }
    return fd
}

func connectTo(fd: Int32, port: UInt16) -> Bool {
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
    return withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
        }
    }
}

func sendAll(fd: Int32, data: Data) {
    _ = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
        var sent = 0
        while sent < data.count {
            let n = send(fd, raw.baseAddress!.advanced(by: sent), data.count - sent, 0)
            if n <= 0 { return false }
            sent += n
        }
        return true
    }
}

/// 返回 (data, isEOF)。区分 poll 超时与真实 EOF。
func recvSomeOrEOF(fd: Int32, timeoutMs: Int32) -> (data: Data?, eof: Bool) {
    var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    guard poll(&pfd, 1, timeoutMs) > 0 else { return (nil, false) }
    var buf = [UInt8](repeating: 0, count: 65536)
    let n = recv(fd, &buf, buf.count, 0)
    if n <= 0 { return (nil, true) }
    return (Data(buf.prefix(n)), false)
}

func readUntil(fd: Int32, contains needle: String, within seconds: Double) -> String {
    var acc = Data()
    let deadline = Date().addingTimeInterval(seconds)
    let needleBytes = Data(needle.utf8)
    while Date() < deadline {
        let (chunk, eof) = recvSomeOrEOF(fd: fd, timeoutMs: 500)
        if let chunk { acc.append(chunk) }
        if acc.range(of: needleBytes) != nil || eof { break }
    }
    return String(data: acc, encoding: .utf8) ?? ""
}

func buildResponsesPayload(
    session: String? = nil,
    kvMaxTokens: Int? = nil,
    prompt: String = "hello"
) -> Data {
    var obj: [String: Any] = ["model": "x", "stream": true, "input": prompt]
    if let session { obj["session_id"] = session }
    if let kv = kvMaxTokens { obj["kvCache"] = ["maxTokens": kv] }
    let body = try! JSONSerialization.data(withJSONObject: obj)
    var head = "POST /v1/responses HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n"
    return Data(head.utf8) + body
}

func extractAssistantText(from sse: String) -> String {
    for line in sse.components(separatedBy: "\n") {
        guard line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String) == "response.completed",
              let response = obj["response"] as? [String: Any],
              let output = response["output"] as? [[String: Any]] else { continue }
        for item in output where (item["type"] as? String) == "message" {
            if let content = item["content"] as? [[String: Any]] {
                return content.compactMap { $0["text"] as? String }.joined()
            }
        }
    }
    return ""
}

func buildResponsesItemsPayload(
    items: [[String: Any]], session: String?, kvMaxTokens: Int? = nil
) -> Data {
    var obj: [String: Any] = ["model": "x", "stream": true, "input": items]
    if let session { obj["session_id"] = session }
    if let kv = kvMaxTokens { obj["kvCache"] = ["maxTokens": kv] }
    let body = try! JSONSerialization.data(withJSONObject: obj)
    var head = "POST /v1/responses HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n"
    return Data(head.utf8) + body
}

// MARK: - trace 断言助手

func traceLineCount() -> Int {
    guard let s = try? String(contentsOfFile: tracePath, encoding: .utf8) else { return 0 }
    return s.components(separatedBy: "\n").count
}

func traceLines(from line: Int) -> [String] {
    guard let s = try? String(contentsOfFile: tracePath, encoding: .utf8) else { return [] }
    let lines = s.components(separatedBy: "\n")
    return line < lines.count ? Array(lines[line...]) : []
}

// MARK: - HTTP 助手（p0 客户端模式）

struct HTTPResult {
    var text: String
    var completed: Bool
    var failed: Bool
    var elapsed: Double
}

func postAndAwait(port: UInt16, payload: Data, timeout: Double) -> HTTPResult {
    guard let fd = try? makeSocket(lingerRST: false), connectTo(fd: fd, port: port) else {
        return HTTPResult(text: "", completed: false, failed: false, elapsed: 0)
    }
    let t0 = Date()
    sendAll(fd: fd, data: payload)
    var acc = Data()
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let (chunk, eof) = recvSomeOrEOF(fd: fd, timeoutMs: 500)
        if let chunk { acc.append(chunk) }
        let text = String(data: acc, encoding: .utf8) ?? ""
        if text.contains("response.completed") || text.contains("response.failed") || eof { break }
    }
    close(fd)
    let text = String(data: acc, encoding: .utf8) ?? ""
    return HTTPResult(
        text: text,
        completed: text.contains("response.completed"),
        failed: text.contains("response.failed"),
        elapsed: Date().timeIntervalSince(t0)
    )
}

// MARK: - 自包含回归场景（stub 服务）

func runNormal() -> Int {
    print("\n===== NORMAL COMPLETION =====")
    guard let fd = try? makeSocket(lingerRST: false), connectTo(fd: fd, port: port) else {
        print("[HARNESS] connect failed"); return 2
    }
    sendAll(fd: fd, data: buildResponsesPayload())
    let seen = readUntil(fd: fd, contains: "response.completed", within: 30)
    close(fd)
    Thread.sleep(forTimeInterval: 0.3)

    let events = ["response.created", "response.in_progress", "response.output_item.added",
                  "response.content_part.added", "response.output_text.delta",
                  "response.output_text.done", "response.content_part.done",
                  "response.output_item.done", "response.completed"]
    var ok = true
    for e in events where !seen.contains(e) {
        print("[HARNESS] MISS \(e)"); ok = false
    }
    let noCancel = recorder.cancelled.isEmpty
    print("[HARNESS] cancels: \(recorder.cancelled)")
    if ok && noCancel { print("=== VERDICT: NORMAL CLEAN ==="); return 0 }
    print("=== VERDICT: NORMAL FAILED ==="); return 1
}

func runCancel() -> Int {
    print("\n===== INTERNAL CANCEL, CLIENT CONNECTED =====")
    guard let fd = try? makeSocket(lingerRST: false), connectTo(fd: fd, port: port) else {
        print("[HARNESS] connect failed"); return 2
    }
    sendAll(fd: fd, data: buildResponsesPayload())
    let seen = readUntil(fd: fd, contains: "response.completed", within: 10)
    let gotFailed = seen.contains("response.failed")
    print("[HARNESS] saw: failed=\(gotFailed)")
    close(fd)
    if gotFailed { print("=== VERDICT: TERMINAL EVENT OBSERVED ==="); return 0 }
    print("=== VERDICT: SILENT HANG ==="); return 1
}

func runDisconnect() -> Int {
    print("\n===== RST DISCONNECT MID-STREAM =====")
    guard let fd = try? makeSocket(lingerRST: true), connectTo(fd: fd, port: port) else {
        print("[HARNESS] connect failed"); return 2
    }
    sendAll(fd: fd, data: buildResponsesPayload())
    let seen = readUntil(fd: fd, contains: "output_text.delta", within: 10)
    guard seen.contains("output_text.delta") else {
        print("[HARNESS] FAIL: no delta before disconnect"); close(fd); return 1
    }
    close(fd)
    print("[HARNESS] client RST mid-stream")
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline, recorder.cancelled.isEmpty {
        Thread.sleep(forTimeInterval: 0.1)
    }
    print("[HARNESS] cancels: \(recorder.cancelled)")
    if recorder.cancelled.isEmpty {
        print("=== VERDICT: DISCONNECT DID NOT CANCEL ==="); return 1
    }
    print("=== VERDICT: DISCONNECT CANCELLED GENERATION ===")
    return 0
}

func runCancelRequeue() -> Int {
    print("\n===== CANCEL A → GATE RELEASED → B RUNS (P0-4) =====")
    guard let fdA = try? makeSocket(lingerRST: true), connectTo(fd: fdA, port: port) else {
        print("[HARNESS] connect failed"); return 2
    }
    sendAll(fd: fdA, data: buildResponsesPayload())
    _ = readUntil(fd: fdA, contains: "output_text.delta", within: 10)
    close(fdA)
    print("[HARNESS] A RST mid-stream")
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline, recorder.cancelled.isEmpty {
        Thread.sleep(forTimeInterval: 0.1)
    }
    print("[HARNESS] A cancel observed: \(recorder.cancelled)")
    guard !recorder.cancelled.isEmpty else {
        print("=== VERDICT: A CANCEL NOT OBSERVED ==="); return 1
    }
    guard let fdB = try? makeSocket(lingerRST: false), connectTo(fd: fdB, port: port) else {
        print("[HARNESS] connect failed"); return 2
    }
    let t0 = Date()
    sendAll(fd: fdB, data: buildResponsesPayload())
    let seen = readUntil(fd: fdB, contains: "response.completed", within: 20)
    let elapsed = Date().timeIntervalSince(t0)
    close(fdB)
    let ok = seen.contains("response.completed")
    print("[HARNESS] B completed=\(ok) elapsed=\(Int(elapsed))s")
    if ok && elapsed < 15 {
        print("=== VERDICT: GATE RELEASED — B RAN PROMPTLY (P0-4 PASS) ==="); return 0
    }
    print("=== VERDICT: B BLOCKED/DELAYED (P0-4 FAIL) ==="); return 1
}

// MARK: - P0 验收矩阵（客户端模式 → 真实 app :8000）

var p0Results: [(String, Bool)] = []

func record(_ name: String, _ pass: Bool) {
    p0Results.append((name, pass))
    print("[HARNESS] ▸ \(pass ? "PASS" : "FAIL")  \(name)")
}

func finishP0() -> Int {
    print("\n===== P0 MATRIX SUMMARY =====")
    var failed = 0
    for (name, pass) in p0Results {
        print("[HARNESS] ▸ \(pass ? "PASS" : "FAIL")  \(name)")
        if !pass { failed += 1 }
    }
    print("===== \(p0Results.count - failed)/\(p0Results.count) PASS =====")
    return failed == 0 ? 0 : 1
}

func runP0() -> Int {
    print("\n===== P0 ACCEPTANCE MATRIX → 127.0.0.1:\(appPort) =====")

    // E (P0-4 核心)：生成中取消 → gate 释放 → 新请求立即生成
    do {
        guard let fd = try? makeSocket(lingerRST: true), connectTo(fd: fd, port: appPort) else {
            record("E connect", false); return finishP0()
        }
        let lineAt = traceLineCount()   // 基线在 E1 发送前捕获，[CANCEL] 必落在窗口内
        sendAll(fd: fd, data: buildResponsesPayload(session: "p0-e", prompt: "Write a story of at least 300 words"))
        _ = readUntil(fd: fd, contains: "output_text.delta", within: 90)
        print("[HARNESS] E1 RST mid-stream（生成中取消）")

        let deadline = Date().addingTimeInterval(10)
        var sawCancelLine = false
        while Date() < deadline {
            if traceLines(from: lineAt).contains(where: { $0.contains("[CANCEL]") }) { sawCancelLine = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard let fd2 = try? makeSocket(lingerRST: false), connectTo(fd: fd2, port: appPort) else {
            record("E2 connect", false); return finishP0()
        }
        let r = postAndAwait(port: appPort, payload: buildResponsesPayload(session: "p0-e"), timeout: 60)
        close(fd2)
        record("E cancel→requeue（B 实际生成）", r.completed && sawCancelLine && r.elapsed < 30)
    }

    // F (P0-5)：同 session，F2 发送累积对话（Codex 同款形态）→ reuse=true
    do {
        let lineAt = traceLineCount()
        let items1: [[String: Any]] = [["role": "user", "content": "hello"]]
        let r1 = postAndAwait(port: appPort, payload: buildResponsesItemsPayload(items: items1, session: "p0-fg"), timeout: 120)
        let assistantText = extractAssistantText(from: r1.text)
        let items2: [[String: Any]] = items1 + [["role": "assistant", "content": assistantText],
                                                ["role": "user", "content": "more"]]
        let r2 = postAndAwait(port: appPort, payload: buildResponsesItemsPayload(items: items2, session: "p0-fg"), timeout: 120)
        print("[HARNESS] assistantText=\(assistantText.prefix(30))…")
        let newLines = traceLines(from: lineAt)
        let reuseHit = newLines.contains { $0.contains("[MLX]") && $0.contains("reuse=true") }
        record("F 同配置累积对话 session reuse", r1.completed && r2.completed && reuseHit && !assistantText.isEmpty)
    }

    // G (P0-5 核心)：同 session 变更 KV 配置 → 禁止复用、全量 prefill
    do {
        let lineAt = traceLineCount()
        let r = postAndAwait(
            port: appPort,
            payload: buildResponsesPayload(session: "p0-fg", kvMaxTokens: 4096),
            timeout: 120
        )
        let newLines = traceLines(from: lineAt)
        let noReuse = newLines.contains { $0.contains("[MLX]") && $0.contains("reuse=false") && $0.contains("kv=") }
        record("G KV 配置变更 → cache 失效全量 prefill", r.completed && noReuse)
    }

    // H：LRU 驱逐（9 个独立 session，超过 sessionLimit=8）
    do {
        let lineAt = traceLineCount()
        var allOK = true
        for i in 1...9 {
            let r = postAndAwait(
                port: appPort,
                payload: buildResponsesPayload(session: "p0-h-\(i)"),
                timeout: 120
            )
            if !r.completed { allOK = false; print("[HARNESS] H\(i) 未完成") }
        }
        let evicted = traceLines(from: lineAt).contains { $0.contains("session LRU evicted") }
        record("H LRU 驱逐触发", allOK && evicted)
    }

    // A (P0-3)：同 session 双并发 → A2 排队（RUNNING 晚于 A1 RELEASED）
    do {
        slowMode.set(true)
        defer { slowMode.set(false) }
        guard let fd1 = try? makeSocket(lingerRST: false), connectTo(fd: fd1, port: appPort) else {
            record("A1 connect", false); return finishP0()
        }
        sendAll(fd: fd1, data: buildResponsesPayload(session: "p0-a", prompt: "Write a story of at least 500 words"))
        _ = readUntil(fd: fd1, contains: "output_text.delta", within: 90)
        let windowStart = traceLineCount()   // A1 已 RUNNING，窗口从 A2 发出前开始
        guard let fd2 = try? makeSocket(lingerRST: false), connectTo(fd: fd2, port: appPort) else {
            record("A2 connect", false); return finishP0()
        }
        sendAll(fd: fd2, data: buildResponsesPayload(session: "p0-a", prompt: "Summarize the story above in one sentence"))
        _ = readUntil(fd: fd2, contains: "response.completed", within: 180)
        close(fd2)
        close(fd1)
        Thread.sleep(forTimeInterval: 0.5)
        let window = traceLines(from: windowStart)
        let runs = window.filter { $0.contains("to=RUNNING") }
        // A2 的 RUNNING 必须晚于 A1 的 [MLX] 完成行（同毫秒时以文件顺序为准）
        let firstMLX = window.firstIndex { $0.contains("[MLX]") }
        let firstRun = runs.first.flatMap { run in window.firstIndex { $0 == run } }
        record("A 同 session 排队（1 RUNNING，晚于 A1 生成完成）", runs.count == 1 && firstMLX != nil && (firstRun ?? -1) > firstMLX!)
    }

    // B (P0-3 全局 gate)：不同 session 双并发 → 仍串行
    do {
        slowMode.set(true)
        defer { slowMode.set(false) }
        guard let fd1 = try? makeSocket(lingerRST: false), connectTo(fd: fd1, port: appPort) else {
            record("B1 connect", false); return finishP0()
        }
        sendAll(fd: fd1, data: buildResponsesPayload(session: "p0-b-1", prompt: "Write a story of at least 500 words"))
        _ = readUntil(fd: fd1, contains: "output_text.delta", within: 90)
        let windowStart = traceLineCount()
        guard let fd2 = try? makeSocket(lingerRST: false), connectTo(fd: fd2, port: appPort) else {
            record("B2 connect", false); return finishP0()
        }
        sendAll(fd: fd2, data: buildResponsesPayload(session: "p0-b-2", prompt: "Write a poem of at least 100 words"))
        _ = readUntil(fd: fd2, contains: "response.completed", within: 180)
        close(fd2)
        close(fd1)
        Thread.sleep(forTimeInterval: 0.5)
        let window = traceLines(from: windowStart)
        let runs = window.filter { $0.contains("to=RUNNING") }
        // B2 的 RUNNING 必须晚于 B1 的 [MLX] 完成行（并发编译死锁时二者重叠）
        let firstMLX = window.firstIndex { $0.contains("[MLX]") }
        let firstRun = runs.first.flatMap { run in window.firstIndex { $0 == run } }
        record("B 跨 session 全局串行（1 新 RUNNING，晚于 B1 生成完成）", runs.count == 1 && firstMLX != nil && (firstRun ?? -1) > firstMLX!)
    }

    // C (P0-3 边界)：排队中的请求被取消 → 零虚假 RUNNING + cancelled_by_client
    do {
        slowMode.set(true)
        defer { slowMode.set(false) }
        guard let fd1 = try? makeSocket(lingerRST: false), connectTo(fd: fd1, port: appPort) else {
            record("C1 connect", false); return finishP0()
        }
        sendAll(fd: fd1, data: buildResponsesPayload(session: "p0-c", prompt: "Write a story of at least 500 words"))
        _ = readUntil(fd: fd1, contains: "output_text.delta", within: 90)
        let windowStart = traceLineCount()
        guard let fd2 = try? makeSocket(lingerRST: true), connectTo(fd: fd2, port: appPort) else {
            record("C2 connect", false); return finishP0()
        }
        sendAll(fd: fd2, data: buildResponsesPayload(session: "p0-c", prompt: "hello"))
        Thread.sleep(forTimeInterval: 1.5)
        close(fd2)
        print("[HARNESS] C2（排队中）RST 取消")
        _ = readUntil(fd: fd1, contains: "response.completed", within: 180)
        close(fd1)
        Thread.sleep(forTimeInterval: 0.5)
        let window = traceLines(from: windowStart)
        let runs = window.filter { $0.contains("to=RUNNING") }.count
        let clientCancel = window.contains { $0.contains("reason=cancelled_by_client") }
        record("C 排队请求取消（0 新 RUNNING + cancelled_by_client）", runs == 0 && clientCancel)
    }

    return finishP0()
}

// MARK: - Main

let exitCode: Int
switch mode {
case "normal": exitCode = runNormal()
case "cancel": exitCode = runCancel()
case "disconnect": exitCode = runDisconnect()
case "cancel_requeue": exitCode = runCancelRequeue()
case "p0": exitCode = runP0()
default: print("usage: harness normal|cancel|disconnect|cancel_requeue|p0"); exit(2)
}
if mode != "p0" { server.stop() }
exit(Int32(exitCode))
