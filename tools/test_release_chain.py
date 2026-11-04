#!/usr/bin/env python3
"""Controls for `tools/release_chain.py`: the chain has to stop, not just run.

The failure this suite pins down was measured, not imagined. A build whose input
list still contained the sanitizer's own rule carriers rewrote them, produced a
file that no longer parses, and the content gate -- which looks for tokens, not
for syntax -- reported PASS on the round that had failed. So the properties tested
here are about failure propagation:

* a stale staging directory cannot be certified by a later round, because the run
  that failed removes the round's own artifacts;
* a step never runs after the step before it has failed;
* the gate is bound to this round's manifest and to the hashes of this round's
  inputs, so an older manifest or changed bytes cannot pass as current;
* a deliverable that no longer parses, or that the privacy audit cannot certify,
  fails the chain even when the gate is satisfied;
* the chain report is written through the redaction rules, because it legitimately
  carries the absolute run paths that the rules exist to keep out of a log;
* the provenance sidecar names the commit and the digest of *this* round, and its
  identity is reproducible from the manifest alone -- the build time and the CI run
  are recorded but do not enter it, and a round that cannot name a commit fails.

Every sensitive value is assembled from parts or imported, so this file itself
carries none of them.
"""

from __future__ import annotations

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_chain as chain  # noqa: E402
import release_sanitize as sanitize  # noqa: E402
import release_staging_audit as staging  # noqa: E402

HOME = "/" + "Users/" + "alice"
CLEAN_DOC = "# SimiGo\n\nProduct documentation.\n"
LEAKY_DOC = "home: " + HOME + "/notes\n"
# Assembled, never written out: this file must not carry the temp-path pattern.
FOLDER_PREFIX = "/" + "private/var/folders/"
REGEX_TAIL = r'[^\s"\'`<>]+")'


def carrier_source() -> str:
    """A .py that contains a copy of the temp-path rule, as the real carriers do.

    Redacting the pattern's own prefix swallows the opening of the character class
    and leaves its tail outside any string, so the built file no longer compiles.
    """
    return "import re\nTEMP_PATH = re.compile(\"" + FOLDER_PREFIX + REGEX_TAIL + "\n"


def git(root: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(root), *args],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr}")
    return result.stdout.strip()


class Repo:
    """A throwaway repo root, its sources, an input manifest naming them, and a commit.

    The commit is not decoration: the last step of the chain has to name a source
    commit, so a control repository that is not a work tree is a different fixture
    than the one the chain expects -- and that difference is itself a test case.
    """

    def __init__(self, root: Path, sources: dict[str, object]) -> None:
        self.root = root
        for name, body in sources.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            if isinstance(body, bytes):
                path.write_bytes(body)
            else:
                path.write_text(body, encoding="utf-8")
        self.inputs = root / "release-inputs.json"
        self.inputs.write_text(json.dumps({
            "manifest_version": 1,
            "sources": [{"path": name, "output": Path(name).name} for name in sources],
        }, indent=2), encoding="utf-8")
        git(root, "init", "-q")
        git(root, "add", "-A")
        git(root, "-c", "user.name=controls", "-c", "user.email=controls@example.invalid",
            "commit", "-q", "-m", "fixture")
        self.commit = git(root, "rev-parse", "HEAD")

    def without_git(self) -> None:
        """Make the source unnameable, the way a plain directory export is."""
        shutil.rmtree(self.root / ".git")

    def dirty(self, name: str = "README.md", body: str = "# Local edit\n") -> None:
        (self.root / name).write_text(body, encoding="utf-8")


class ChainTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)
        self.work = self.tmp / "run"

    def repo(self, **sources: object) -> Repo:
        if sources:
            return Repo(self.tmp / "repo", sources)
        return Repo(self.tmp / "repo", {"README.md": CLEAN_DOC})

    def run_chain(self, repo: Repo, exclusions: Path | None = None) -> tuple[dict, int]:
        return chain.run(repo.inputs, self.work, repo.root, exclusions)

    def capture(self, repo: Repo) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = chain.main(["--inputs", str(repo.inputs), "--work", str(self.work),
                               "--root", str(repo.root)])
        return code, out.getvalue() + err.getvalue()

    # ---- the happy path, and what it is allowed to claim ---------------------

    def test_a_clean_round_runs_every_step(self) -> None:
        repo = self.repo(**{"README.md": CLEAN_DOC,
                            "docs/leaky.md": LEAKY_DOC,
                            "tools/carrier.py": "print('ok')\n"})
        report, code = self.run_chain(repo)
        self.assertEqual(code, 0, report["detail"])
        self.assertEqual([entry["step"] for entry in report["steps"]], list(chain.STEPS))
        self.assertTrue(all(entry["status"] == "pass" for entry in report["steps"]))
        self.assertEqual(report["failed_step"], None)
        self.assertEqual(report["staging_audit"]["checked"], 3)
        self.assertTrue((self.work / "tree" / "leaky.md").read_text().startswith("home: <HOME>"))

    def test_the_cli_reports_the_pass_on_stdout_only(self) -> None:
        code, transcript = self.capture(self.repo())
        self.assertEqual(code, 0)
        self.assertIn("CHAIN RESULT = PASS", transcript)
        self.assertIn("no step skipped", transcript)
        self.assertIn("neither verdict implies the other", transcript)

    # ---- a failed build must not leave anything to certify -------------------

    def test_a_build_failure_stops_every_later_step(self) -> None:
        repo = self.repo(**{"README.md": CLEAN_DOC, "evidence/blob.bin": b"\xff\xfe\x00bin"})
        report, code = self.run_chain(repo)
        self.assertEqual(code, 1)
        self.assertEqual(report["failed_step"], "build")
        self.assertEqual(report["not_run"],
                         ["syntax", "input-hashes", "gate", "staging-audit", "provenance"])
        self.assertNotIn("gate", [entry["step"] for entry in report["steps"]])
        self.assertFalse((self.work / "tree").exists(),
                         "a failed round must leave no staging tree")
        self.assertFalse((self.work / "provenance.json").exists())

    def test_a_stale_tree_cannot_be_certified_by_a_later_round(self) -> None:
        # The measured incident: a previous round's deliverable survives, the current
        # build fails, and a gate pointed at that directory still says PASS about
        # bytes this round never built.
        good = self.repo()
        code, _ = self.capture(good)
        self.assertEqual(code, 0)
        tree = self.work / "tree"
        self.assertEqual(sanitize.gate(tree, self.work / "provenance.json"), [],
                         "the first round really did produce a certifiable tree")

        bad = Repo(self.tmp / "bad-repo", {"README.md": CLEAN_DOC,
                                           "evidence/blob.bin": b"\xff\xfe\x00bin"})
        report, code = chain.run(bad.inputs, self.work, bad.root)
        self.assertEqual(code, 1)
        self.assertIn("tree", report["cleaned"], "the stale round was cleared first")
        self.assertIn("provenance.json", report["cleaned"])
        self.assertEqual(report["failed_step"], "build")
        self.assertFalse(tree.exists())
        self.assertTrue(sanitize.gate(tree, self.work / "provenance.json"),
                        "nothing is left for a later gate to pass")

    def test_no_later_step_is_even_called_after_a_build_failure(self) -> None:
        # Not only the verdict: the gate and the audit must never be reached, so a
        # failed build cannot be overruled by whatever they would have reported.
        calls: list[str] = []
        real_gate, real_audit = sanitize.gate, chain.staging.audit

        def spy_gate(*args, **kwargs):
            calls.append("gate")
            return real_gate(*args, **kwargs)

        def spy_audit(*args, **kwargs):
            calls.append("staging-audit")
            return real_audit(*args, **kwargs)

        repo = self.repo(**{"README.md": CLEAN_DOC, "evidence/blob.bin": b"\xff\xfe\x00bin"})
        sanitize.gate, chain.staging.audit = spy_gate, spy_audit
        try:
            report, code = self.run_chain(repo)
        finally:
            sanitize.gate, chain.staging.audit = real_gate, real_audit
        self.assertEqual(code, 1)
        self.assertEqual(report["failed_step"], "build")
        self.assertEqual(calls, [], "a failed build must not reach the gate or the audit")

    def test_a_run_directory_it_does_not_own_is_refused_intact(self) -> None:
        self.work.mkdir()
        foreign = self.work / "someones-notes.md"
        foreign.write_text(CLEAN_DOC, encoding="utf-8")
        report, code = self.run_chain(self.repo())
        self.assertEqual(code, 1)
        self.assertEqual(report["failed_step"], "clean")
        self.assertTrue(foreign.exists(), "the chain deletes its own artifacts, never a stranger")
        self.assertEqual(report["removed_after_failure"], [])

    # ---- the gate cannot see a build that broke the file ---------------------

    def test_a_redaction_that_breaks_a_file_fails_before_the_gate(self) -> None:
        repo = self.repo(**{"README.md": CLEAN_DOC,
                            "tools/release_carrier.py": carrier_source()})
        report, code = self.run_chain(repo)
        self.assertEqual(code, 1)
        self.assertEqual(report["failed_step"], "syntax")
        self.assertEqual(report["not_run"],
                         ["input-hashes", "gate", "staging-audit", "provenance"])
        self.assertIn("release_carrier.py", report["detail"])

        # Why the step exists: build the same input by hand and the content gate is
        # satisfied by a deliverable that no longer parses.
        scratch = self.tmp / "manual"
        manual = sanitize.build(repo.inputs, scratch / "tree", scratch / "provenance.json",
                                repo.root)
        self.assertEqual(len(manual["sources"]), 2)
        self.assertEqual(sanitize.gate(scratch / "tree", scratch / "provenance.json"), [],
                         "the gate reports PASS on the broken file")
        with self.assertRaises(SyntaxError):
            compile((scratch / "tree" / "release_carrier.py").read_text(encoding="utf-8"),
                    "release_carrier.py", "exec")

    def test_a_file_the_build_did_not_rewrite_is_not_judged_here(self) -> None:
        # Deliberate scope, so the step cannot be read as a general Python check:
        # the question is "did redaction break this file?", not "is the repository's
        # Python valid?". An untouched file is the repository audit's business.
        repo = self.repo(**{"README.md": CLEAN_DOC, "tools/untouched.py": "not python (\n"})
        report, code = self.run_chain(repo)
        self.assertEqual(code, 0, report["detail"])
        entry = [item for item in report["steps"] if item["step"] == "syntax"][0]
        self.assertEqual(entry["redacted_python"], 0)
        self.assertEqual(entry["unchanged_python_files_not_judged"], 1)

    def test_an_uncertifiable_container_fails_the_chain_after_a_passing_gate(self) -> None:
        repo = self.repo(**{"README.md": CLEAN_DOC, "docs/shot.png": "not a png\n"})
        scratch = self.tmp / "manual"
        sanitize.build(repo.inputs, scratch / "tree", scratch / "provenance.json", repo.root)
        self.assertEqual(sanitize.gate(scratch / "tree", scratch / "provenance.json"), [],
                         "the gate has no container engine")

        report, code = self.run_chain(repo)
        self.assertEqual(code, 1)
        self.assertEqual(report["failed_step"], "staging-audit")
        self.assertTrue(report["staging_audit"]["container_errors"])
        self.assertFalse((self.work / "tree").exists(),
                         "a refused deliverable is not left in place to be re-used")

    # ---- the gate is bound to this round's bytes -----------------------------

    def test_inputs_changed_after_the_build_are_detected(self) -> None:
        repo = self.repo(**{"README.md": CLEAN_DOC})
        scratch = self.tmp / "manual"
        sanitize.build(repo.inputs, scratch / "tree", scratch / "provenance.json", repo.root)
        self.assertEqual(chain.check_input_hashes(repo.inputs, scratch / "provenance.json",
                                                  repo.root), [])
        (repo.root / "README.md").write_text("# Changed\n", encoding="utf-8")
        errors = chain.check_input_hashes(repo.inputs, scratch / "provenance.json", repo.root)
        self.assertEqual(errors, ["input changed after the build: README.md"])

        (repo.root / "README.md").unlink()
        self.assertEqual(
            chain.check_input_hashes(repo.inputs, scratch / "provenance.json", repo.root),
            ["input disappeared after the build: README.md"])

    def test_a_manifest_from_a_different_input_set_is_not_this_rounds(self) -> None:
        repo = self.repo(**{"README.md": CLEAN_DOC})
        scratch = self.tmp / "manual"
        sanitize.build(repo.inputs, scratch / "tree", scratch / "provenance.json", repo.root)
        other = self.tmp / "other-inputs.json"
        other.write_text(json.dumps({"manifest_version": 1, "sources": [
            {"path": "README.md", "output": "README.md"},
            {"path": "extra.md", "output": "extra.md"}]}), encoding="utf-8")
        errors = chain.check_input_hashes(other, scratch / "provenance.json", repo.root)
        self.assertIn("the manifest does not list the same sources as the input manifest",
                      errors)

    def test_a_manifest_from_another_rules_version_is_rejected_by_the_gate(self) -> None:
        repo = self.repo(**{"README.md": CLEAN_DOC})
        scratch = self.tmp / "manual"
        sanitize.build(repo.inputs, scratch / "tree", scratch / "provenance.json", repo.root)
        stale = json.loads((scratch / "provenance.json").read_text(encoding="utf-8"))
        stale["rules_version"] = "sanitize-2026-01-01.1"
        (scratch / "provenance.json").write_text(json.dumps(stale), encoding="utf-8")
        errors = sanitize.gate(scratch / "tree", scratch / "provenance.json")
        self.assertTrue(any("rules_version" in error for error in errors), errors)

    # ---- the report itself must be publishable --------------------------------

    def test_the_report_redacts_the_absolute_run_paths(self) -> None:
        repo = Repo(self.tmp / "Users" / "alice" / "repo",
                    {"README.md": CLEAN_DOC, "docs/leaky.md": LEAKY_DOC})
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = chain.main(["--inputs", str(repo.inputs), "--work", str(self.work),
                               "--root", str(repo.root), "--report", str(self.tmp / "r.json")])
        self.assertEqual(code, 0)
        printed = out.getvalue() + err.getvalue()
        stored = (self.tmp / "r.json").read_text(encoding="utf-8")
        sidecar = (self.work / chain.PROVENANCE_NAME).read_text(encoding="utf-8")
        for text in (printed, stored, sidecar,
                     (self.work / "chain.json").read_text(encoding="utf-8")):
            self.assertNotIn(HOME, text)
            self.assertNotIn(FOLDER_PREFIX, text)
        self.assertIn("<HOME>", stored)
        self.assertIn("<HOME>", sidecar)
        self.assertIn("RESULT", printed)

    def test_the_deliverable_of_a_passing_round_is_clean_by_itself(self) -> None:
        # The chain verdict and a standalone audit of the same directory have to
        # agree; if they did not, the chain would be asserting something its own
        # engine cannot reproduce.
        repo = self.repo(**{"README.md": CLEAN_DOC, "docs/leaky.md": LEAKY_DOC})
        code, _ = self.capture(repo)
        self.assertEqual(code, 0)
        report = staging.audit(self.work / "tree")
        self.assertEqual(report["artifact_hits"], [])
        self.assertEqual(report["sanitize_hits"], [])
        self.assertEqual(report["container_errors"], [])
        self.assertEqual(report["checked"], 2)
        self.assertEqual(report["rules"], staging.RULES)

    # ---- the provenance sidecar ----------------------------------------------

    def sidecar(self) -> dict:
        return json.loads((self.work / chain.PROVENANCE_NAME).read_text(encoding="utf-8"))

    def test_the_sidecar_names_the_commit_and_a_digest_that_replays(self) -> None:
        repo = self.repo(**{"README.md": CLEAN_DOC, "docs/leaky.md": LEAKY_DOC})
        report, code = self.run_chain(repo)
        self.assertEqual(code, 0, report["detail"])
        side = self.sidecar()
        identity = side["identity"]
        self.assertEqual(identity["source_commit"], repo.commit)
        self.assertEqual(identity["source_tree"], git(repo.root, "rev-parse", "HEAD^{tree}"))
        self.assertEqual(side["source"]["inputs_at_commit"], True)
        self.assertEqual(side["source"]["inputs_named"], 2)
        self.assertEqual(side["source"]["inputs_tracked"], 2)
        self.assertEqual(side["source"]["inputs_differing_from_commit"], 0)
        # Replay: the digest is recomputable from this round's manifest, file by file.
        records = json.loads((self.work / "provenance.json").read_text())["sources"]
        self.assertEqual(identity["staging_digest"],
                         chain.deliverable_digest(self.work / "tree", records))
        self.assertEqual(side["identity_sha256"],
                         chain._sha256(json.dumps(identity, sort_keys=True,
                                                  separators=(",", ":")).encode("utf-8")))
        self.assertEqual(sorted(identity), sorted(chain.IDENTITY_FIELDS))
        self.assertEqual(sorted(identity["tool_sha256"]), sorted(chain.TOOL_FILES))
        self.assertEqual(side["deliverable"], {"files": 2, "redacted_files": 1,
                                               "bytes": sum(r["output_bytes"]
                                                            for r in records)})

    def test_the_digest_recipe_is_a_stated_ordering_not_an_incidental_one(self) -> None:
        # The recipe is "output\thash\n" lines sorted by the output string. Pinning it
        # matters: sorting by path components instead is a plausible way to re-derive
        # the same digest and gives a different answer on any nested deliverable, so a
        # reviewer who did that would be chasing changed bytes that are not there.
        tree = self.tmp / "tree"
        (tree / "a").mkdir(parents=True)
        (tree / "a" / "b.txt").write_text("x", encoding="utf-8")
        records = [{"output": "a/b.txt", "output_sha256": "h1"},
                   {"output": "a.txt", "output_sha256": "h2"}]
        self.assertEqual(chain.deliverable_digest(tree, records),
                         chain._sha256(b"a.txt\th2\na/b.txt\th1\n"))
        self.assertNotEqual(chain.deliverable_digest(tree, records),
                            chain._sha256(b"a/b.txt\th1\na.txt\th2\n"))
        with self.assertRaises(chain.ChainError):
            chain.deliverable_digest(tree, [])

    def test_a_manifest_that_names_a_missing_file_has_no_digest(self) -> None:
        records = [{"output": "gone.md", "output_sha256": "h"}]
        with self.assertRaises(chain.ChainError):
            chain.deliverable_digest(self.tmp / "empty-tree", records)

    def test_the_identity_excludes_the_build_time_and_the_ci_run(self) -> None:
        # The point of `#242`: the deterministic identity has to survive a re-cut of
        # the same tree at another moment, on another machine, with or without a CI
        # run id. Two rounds that differ only in *when* and *where* they ran must
        # agree, or the identity would be a receipt rather than a fingerprint.
        repo = self.repo(**{"README.md": CLEAN_DOC, "docs/leaky.md": LEAKY_DOC})
        real_clock, real_env = chain.build_timestamp, os.environ.copy()
        rounds = []
        try:
            for stamp, run_id in (("2026-01-01T00:00:00+00:00", None),
                                  ("2027-02-02T02:02:02+00:00", None),
                                  ("2028-03-03T03:03:03+00:00", "12345")):
                chain.build_timestamp = lambda value=stamp: value
                if run_id is None:
                    os.environ.pop("GITHUB_RUN_ID", None)
                else:
                    os.environ["GITHUB_RUN_ID"] = run_id
                report, code = self.run_chain(repo)
                self.assertEqual(code, 0, report["detail"])
                rounds.append(self.sidecar())
        finally:
            chain.build_timestamp = real_clock
            os.environ.clear()
            os.environ.update(real_env)
        self.assertEqual([side["build_time"] for side in rounds],
                         ["2026-01-01T00:00:00+00:00", "2027-02-02T02:02:02+00:00",
                          "2028-03-03T03:03:03+00:00"])
        self.assertEqual([side["ci"]["run_id"] for side in rounds], [None, None, "12345"])
        self.assertEqual([side["ci"]["explicitly_local"] for side in rounds],
                         [True, True, False])
        self.assertEqual(len({side["identity_sha256"] for side in rounds}), 1,
                         "the identity moved with the clock or the CI run")
        for side in rounds:
            for excluded in chain.NOT_IN_IDENTITY:
                self.assertNotIn(excluded, side["identity"])
            self.assertEqual(side["identity_excludes"], list(chain.NOT_IN_IDENTITY))

    def test_a_register_that_was_not_passed_is_said_not_guessed(self) -> None:
        repo = self.repo(**{"README.md": CLEAN_DOC})
        register = self.tmp / "release-exclusions.json"
        register.write_text(json.dumps({"manifest_version": 1, "excluded": []}),
                            encoding="utf-8")
        report, code = self.run_chain(repo, register)
        self.assertEqual(code, 0, report["detail"])
        self.assertEqual(self.sidecar()["identity"]["exclusions_manifest_sha256"],
                         chain._sha256(register.read_bytes()))

        report, code = self.run_chain(repo)
        self.assertEqual(code, 0, report["detail"])
        side = self.sidecar()
        self.assertEqual(side["identity"]["exclusions_manifest_sha256"], chain.NO_REGISTER)
        self.assertEqual(side["exclusions_manifest"], chain.NO_REGISTER)

    def test_a_source_that_cannot_be_named_fails_the_last_step(self) -> None:
        # Paired with the test above: a directory export with no commit in it is not
        # a round with unknown provenance, it is a round with no provenance. The tree
        # the earlier steps certified is removed with the failure, so nothing is left
        # that a later reader could take for a deliverable of this chain.
        repo = self.repo(**{"README.md": CLEAN_DOC, "docs/leaky.md": LEAKY_DOC})
        repo.without_git()
        report, code = self.run_chain(repo)
        self.assertEqual(code, 1)
        self.assertEqual(report["failed_step"], "provenance")
        self.assertEqual(report["not_run"], [])
        self.assertFalse((self.work / "tree").exists())
        self.assertFalse((self.work / chain.PROVENANCE_NAME).exists())
        self.assertNotIn("provenance", report)

    def test_a_dirty_input_is_recorded_and_the_round_does_not_claim_replay(self) -> None:
        # The chain certifies the bytes it built -- the input-hashes step proves that.
        # Whether those bytes are the bytes `source_commit` names is a separate reading,
        # and an unrelated edit inside one declared input has to show up in it rather
        # than being inferred from a green run.
        repo = self.repo(**{"README.md": CLEAN_DOC, "docs/leaky.md": LEAKY_DOC})
        repo.dirty()
        report, code = self.run_chain(repo)
        self.assertEqual(code, 0, report["detail"])
        side = self.sidecar()
        self.assertEqual(side["source"]["inputs_at_commit"], False)
        self.assertEqual(side["source"]["inputs_differing_from_commit"], 1)
        entry = [item for item in report["steps"] if item["step"] == "provenance"][0]
        self.assertEqual(entry["inputs_at_commit"], False)

    def test_the_provenance_step_is_never_reached_after_a_failed_audit(self) -> None:
        calls: list[str] = []
        real_provenance = chain.provenance

        def spy(*args, **kwargs):
            calls.append("provenance")
            return real_provenance(*args, **kwargs)

        repo = self.repo(**{"README.md": CLEAN_DOC, "docs/shot.png": "not a png\n"})
        chain.provenance = spy
        try:
            report, code = self.run_chain(repo)
        finally:
            chain.provenance = real_provenance
        self.assertEqual(code, 1)
        self.assertEqual(report["failed_step"], "staging-audit")
        self.assertEqual(calls, [], "a refused deliverable gets no provenance")
        self.assertFalse((self.work / chain.PROVENANCE_NAME).exists())


if __name__ == "__main__":
    unittest.main()
