# Security Policy

## Supported version

Security fixes target the latest published release and `main`. At present this
is the `v2.1.0` Execution State Reference App line.

## Reporting a vulnerability

Use GitHub's **Private vulnerability reporting** for this repository. Do not
open a public issue with exploit steps, request payloads, model paths, or local
network topology.

Please include:

- affected commit or release;
- macOS/App Build version;
- minimal reproduction;
- impact you observed;
- whether the issue affects HTTP, persistence, external process launch, or the
  model backend.

We aim to acknowledge reports within five business days and will coordinate a
disclosure date with the reporter.

## Security scope

SimiGo executes models and provides an OpenAI-compatible HTTP service. Priority
areas include:

- HTTP request parsing and streaming responses;
- LAN binding and process lifecycle;
- tool-call validation and external agent handoff;
- checkpoint, prefix-pool, and state-graph persistence;
- restore/validation paths that must fail closed;
- external `llama-server` process invocation;
- model-directory selection and access to local files.

## Current research boundary

SimiGo is a research preview, not a hardened multi-tenant service.

The LAN mode currently has **no authentication**. Do not expose it to the public
internet or run it on an untrusted network. Keep the API on localhost unless you
understand the trust boundary. Model files, checkpoints, and state snapshots are
local trusted inputs; do not point SimiGo at untrusted archives.

## Out of scope

The following are product-quality reports rather than security vulnerabilities
unless they cross a privilege or filesystem trust boundary:

- generation quality;
- model performance or memory pressure;
- OpenAI protocol feature differences;
- lack of cluster authentication in research preview mode.
