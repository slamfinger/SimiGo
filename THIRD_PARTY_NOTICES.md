# Third-Party Notices

SimiGo depends on third-party software. Those components are not relicensed by
this repository. The SPDX identifiers below record the license found in each
pinned dependency at the time of the v2.1 packaging audit.

## Runtime dependencies

| Component | Source | License |
|---|---|---|
| EventSource | https://github.com/mattt/EventSource | MIT |
| MLX Swift | https://github.com/ml-explore/mlx-swift | MIT |
| MLX Swift LM | https://github.com/ml-explore/mlx-swift-examples | MIT |
| Swift ASN.1 | https://github.com/apple/swift-asn1 | Apache-2.0 |
| Swift Collections | https://github.com/apple/swift-collections | Apache-2.0 |
| Swift Crypto | https://github.com/apple/swift-crypto | Apache-2.0 |
| Swift HuggingFace | https://github.com/huggingface/swift-huggingface | Apache-2.0 |
| Swift Jinja | https://github.com/huggingface/swift-jinja | Apache-2.0 |
| Swift Numerics | https://github.com/apple/swift-numerics | Apache-2.0 |
| Swift Syntax | https://github.com/swiftlang/swift-syntax | Apache-2.0 |
| Swift Transformers | https://github.com/huggingface/swift-transformers | Apache-2.0 |
| yyjson | https://github.com/ibireme/yyjson | MIT |

The project may use forked MLX repositories to pin runtime APIs. Forking does
not change upstream ownership or license terms.

## Optional external runtime

llama.cpp is optional and may be supplied by the user as an external process.
It is not embedded in this repository. llama.cpp is MIT-licensed upstream;
users must verify the exact source/build they install.

## Models and data

No model weights are distributed with SimiGo. Tests that require a local model
are environment-gated and skip when `SIMIGO_FORK_MODEL` is absent. Every model
remains governed solely by its upstream license.
