# Security Policy

## Supported versions

Security fixes target the current main branch and any explicitly published release that is still supported. As of the 2026-11-05 repository review, the GitHub Releases API returned no published Release records, so no published release is a support target until one appears there. Check the root [README.md](README.md) for current distribution status.

## Reporting a vulnerability

Use GitHub's **Private vulnerability reporting** for this repository. Do not open a public issue with exploit steps, request payloads, model paths, or local network topology.

Please include:

- affected commit or release;
- macOS/App Build version;
- minimal reproduction;
- impact you observed;
- whether the issue affects HTTP, persistence, external process launch, or the model backend.

We aim to acknowledge reports within five business days and will coordinate a disclosure date with the reporter.

## Security scope

SimiGo executes models and provides an OpenAI-compatible HTTP service. Priority areas include:

- HTTP request parsing and streaming responses;
- listener binding, transport security, and process lifecycle;
- tool-call validation and external agent handoff;
- checkpoint, prefix-pool, and state-graph persistence;
- restore/validation paths that must fail closed;
- external llama-server process invocation;
- model-directory selection and access to local files.

## Current security boundary

SimiGo is a single-user local runtime, not a hardened multi-tenant service.

The local API binds to loopback by default. Do not expose it to the public internet or an untrusted network. Non-loopback access must use the product's TLS/authentication path; review [Agent Access](docs/AGENT-ACCESS.md) and the specific configuration in use rather than assuming localhost protections apply to LAN deployments. Keep model files, checkpoints, and state snapshots as trusted local inputs; do not point SimiGo at untrusted archives.

Report any discrepancy between the documented security boundary and the behavior of a particular release or build.

## Out of scope

Generation quality, model performance or memory pressure, and OpenAI protocol feature differences are product-quality reports unless they cross a privilege, transport, or filesystem trust boundary.
