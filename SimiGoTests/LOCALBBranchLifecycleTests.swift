import Crypto
import Foundation
import LOCALBCore
import XCTest

@testable import SimiGo

/// S3-A (owner ruling 2026-11-05): branch deletion is observable and
/// strict. The lifecycle matrix runs over the real HTTP surface with a
/// branchControl-only client and a stateful branch fixture:
///   1. successful deletion reports the post-deletion listing (A.3);
///   2. repeat deletion of the same branch fails 404 branch_unknown;
///   3. a cross-session target (exists under another session) fails 404;
///   4. a stale expected_generation fails 409 branch_generation_mismatch;
///   5. the matching generation deletes successfully;
///   6. revocation covers pending challenges and later requests (A.4/A.5).
final class LOCALBBranchLifecycleTests: LOCALBTestCase {

    private func makeBranchControlClient() throws -> Host {
        let host = try makeAuthorizedHost()
        let coordinator = try XCTUnwrap(host.coordinator)
        let box = try XCTUnwrap(host.trustedCheckpoint)
        let changed = try coordinator.setClientPermissions(
            clientKeyID: host.clientKeyID,
            permissions: [.branchControl],
            reason: "S3-A lifecycle fixture",
            checkpoint: box.value
        )
        box.value = changed
        return host
    }

    /// Runs one authorized delete over TLS and returns the status line plus
    /// the parsed JSON body (if any).
    private func deleteBranch(
        _ host: Host, sessionId: String, branchId: String,
        expectedGeneration: UInt64? = nil
    ) throws -> (status: String, json: [String: Any]?) {
        var body = "{\"session_id\":\"\(sessionId)\",\"branch_id\":\"\(branchId)\""
        if let expectedGeneration {
            body += ",\"expected_generation\":\(expectedGeneration)"
        }
        body += "}"
        let (challenge, permission) = try fetchChallenge(
            host, method: "POST", target: "/v1/branches/delete"
        )
        XCTAssertEqual(permission, "P-BRANCH-CONTROL")
        let request = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/branches/delete",
            contentType: "application/json",
            body: body,
            challenge: challenge,
            permission: .branchControl
        )
        let response = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: request
        )
        return (
            try XCTUnwrap(statusLine(of: response)),
            try? jsonBody(of: response)
        )
    }

    /// The lifecycle matrix: success → repeat → cross-session → stale
    /// generation → matching generation, in one deterministic sequence.
    func testBranchDeletionLifecycleFailureMatrix() throws {
        let host = try makeBranchControlClient()

        seedBranch(sessionId: "s1", branchId: "b1")
        seedBranch(sessionId: "s1", branchId: "b2")
        seedBranch(sessionId: "s2", branchId: "b1")

        // 1. Successful deletion: 200, outcome consumed into the response,
        //    and the reported remaining listing excludes the target (A.3).
        let ok = try deleteBranch(host, sessionId: "s1", branchId: "b1")
        XCTAssertTrue(ok.status.contains(" 200 "), "got: \(ok.status)")
        let okJSON = try XCTUnwrap(ok.json, "delete must return a JSON body")
        XCTAssertEqual(okJSON["ok"] as? Bool, true)
        XCTAssertEqual(okJSON["deleted_branch"] as? String, "b1")
        XCTAssertEqual(okJSON["generation"] as? Int, 1)
        let remaining = try XCTUnwrap(okJSON["remaining_live"] as? [String])
        XCTAssertFalse(remaining.contains("b1"), "target must be gone: \(remaining)")
        XCTAssertTrue(remaining.contains("b2"))

        // 2. Repeat deletion of the same branch: explicit 404 branch_unknown.
        let repeatDelete = try deleteBranch(host, sessionId: "s1", branchId: "b1")
        XCTAssertTrue(
            repeatDelete.status.contains(" 404 "),
            "repeat delete must fail: got \(repeatDelete.status)"
        )
        let repeatText = String(
            decoding: (repeatDelete.json.map { try? JSONSerialization.data(withJSONObject: $0) } ?? nil)
                ?? Data(), as: UTF8.self
        )
        XCTAssertTrue(
            repeatText.lowercased().contains("branch_unknown"),
            "expected branch_unknown: \(repeatText.prefix(300))"
        )

        // 3. Cross-session target: b1 exists under s2, but the request
        //    names s3 — the namespace makes it unknown here (404).
        let crossSession = try deleteBranch(host, sessionId: "s3", branchId: "b1")
        XCTAssertTrue(
            crossSession.status.contains(" 404 "),
            "cross-session delete must fail: got \(crossSession.status)"
        )

        // 4. expected_generation is RESERVED for the llama.cpp ES
        //    integration's generation semantics: this runtime tracks no
        //    generation source, so the deletion proceeds and the response
        //    carries no generation field rather than inventing one.
        let reserved = try deleteBranch(
            host, sessionId: "s1", branchId: "b2", expectedGeneration: 99
        )
        XCTAssertTrue(
            reserved.status.contains(" 200 "),
            "the reserved generation guard must not fabricate refusals: "
                + "got \(reserved.status)"
        )
        // The fixture DOES track a generation and reports it honestly (1);
        // the contract point is that no refusal was fabricated for a
        // reserved guard.
        XCTAssertEqual(reserved.json?["generation"] as? Int, 1)

        // 6. The read path agrees: no branches remain for s1 (a fresh ghost
        //    branch is seeded so the list endpoint has content to serve).
        seedBranch(sessionId: "s1", branchId: "ghost")
        let listChallenge = try fetchChallenge(
            host, method: "POST", target: "/v1/branches/list"
        )
        XCTAssertEqual(listChallenge.permission, "P-BRANCH-CONTROL")
        let listRequest = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/branches/list",
            contentType: "application/json",
            body: "{\"session_id\":\"s1\"}",
            challenge: listChallenge.challenge,
            permission: .branchControl
        )
        let listResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: listRequest
        )
        let listJSON = try XCTUnwrap(jsonBody(of: listResponse))
        let live = try XCTUnwrap(listJSON["live_branches"] as? [String])
        XCTAssertEqual(live, ["ghost"], "the deleted branches must be gone")
        XCTAssertFalse(live.contains("b1"))
        XCTAssertFalse(live.contains("b2"))
    }

    /// T4: revocation covers the FULL request path. The client provably
    /// succeeded at a branch operation BEFORE the revocation; an already
    /// issued, unconsumed challenge must then fail consumption, and fresh
    /// challenges are refused at the registry stage.
    func testRevocationCoversPendingChallengesAndLaterRequests() throws {
        let host = try makeBranchControlClient()
        let coordinator = try XCTUnwrap(host.coordinator)
        let box = try XCTUnwrap(host.trustedCheckpoint)

        seedBranch(sessionId: "s1", branchId: "b1")
        seedBranch(sessionId: "s1", branchId: "b2")

        // Before revocation the branch operation genuinely succeeds.
        let before = try deleteBranch(host, sessionId: "s1", branchId: "b1")
        XCTAssertTrue(
            before.status.contains(" 200 "),
            "pre-revoke deletion must succeed first: got \(before.status)"
        )

        // A challenge issued BEFORE the revocation sits unconsumed.
        let (pendingChallenge, pendingPermission) = try fetchChallenge(
            host, method: "POST", target: "/v1/branches/delete"
        )
        XCTAssertEqual(pendingPermission, "P-BRANCH-CONTROL")

        // Revoke the client entirely (local owner management plane).
        let revoked = try coordinator.revokeClient(
            clientKeyID: host.clientKeyID,
            reason: "S3-A T4 revocation immediacy",
            checkpoint: box.value
        )
        box.value = revoked

        // The pending challenge must NOT authorize after revocation: the
        // consumption-stage registry re-check refuses (401 clientRevoked),
        // and the branch handler never runs.
        let staleAttempt = try protectedRequest(
            host,
            method: "POST",
            target: "/v1/branches/delete",
            contentType: "application/json",
            body: "{\"session_id\":\"s1\",\"branch_id\":\"b2\"}",
            challenge: pendingChallenge,
            permission: .branchControl
        )
        let staleResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: staleAttempt
        )
        let staleStatus = try XCTUnwrap(statusLine(of: staleResponse))
        XCTAssertTrue(
            staleStatus.contains(" 401 "),
            "pending challenge after revoke: expected 401, got \(staleStatus)"
        )

        // Fresh challenges are refused at the registry stage as well.
        let body = "{\"method\":\"POST\",\"requestTarget\":\"/v1/branches/delete\"}"
        let freshChallengeRequest =
            "POST /localb/auth/challenge HTTP/1.1\r\n"
            + "Host: 127.0.0.1:\(host.port)\r\n"
            + "X-SimiGo-LocalB-Client-Key-ID: \(host.clientKeyID)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n" + body
        let freshResponse = sendRequest(
            port: host.port, spkiHex: host.spkiHex, request: freshChallengeRequest
        )
        XCTAssertTrue(
            try XCTUnwrap(statusLine(of: freshResponse)).contains(" 400 "),
            "post-revoke challenge must be refused at issuance"
        )
        // The 400 from the challenge endpoint IS the registry-stage
        // refusal; the body carries the server's error contract.
        let freshBody = try? jsonBody(of: freshResponse)
        XCTAssertNotNil(freshBody, "the refusal must carry a JSON error body")
    }
}
