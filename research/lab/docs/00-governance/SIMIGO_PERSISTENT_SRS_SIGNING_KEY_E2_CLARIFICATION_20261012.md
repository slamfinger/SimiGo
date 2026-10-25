# E2 Technical Clarification — Test-Derived Key vs Production Anchor

> **Status:** DRAFT — NOT YET COMMITTED (awaiting governance review)
> **Date:** 2026-10-12
> **Supplements (does not modify):** Signing Key Custody Fact-Finding Record,
> commit `8d193c557aee0fb132d9929ae55ffecf966b6a14`

## 1. Production signing interface facts

`SRSVALDecisionCore.swift` publicly exposes:

```text
SRSVALIssuer(rawPrivateKey: Data)   — builds an Ed25519 signing key and
                                      publishes its public key;
SRSVALIssuer.seal(payload, domain)  — signs a canonical payload.
```

Two distinct facts must not be conflated:

```text
fact A: the production module PROVIDES a signing interface;
fact B: a lawful production signing CAPABILITY exists (a custodian holds the
  private key bound to the frozen production anchor public key).
```

The custody audit confirmed neither A nor B implies the other; no production
call site constructs an issuer, and no custodian is identified.

## 2. Direct derivation and byte-level comparison (performed 2026-10-12)

Verification boundary: no Swift Build/Test was executed for this
clarification, and no Swift-side runtime cross-validation was performed. The
results below come from direct computation and byte-level comparison using
Python `cryptography`; they must not be described as both implementations
having passed a runtime cross-validation.

Computation environment version: the `cryptography` library version of the
original execution environment was not recorded at execution time and cannot
be retroactively recovered; per governance instruction, no current-environment
version is substituted for it. The recorded facts (seed, derived public key,
digests, comparison) are unaffected by this limitation, and the derivation can
be reproduced with any compliant Ed25519 implementation per section 3.

Method: the test key input is derived exactly as in
`Tests/SRSVALDecisionCoreTests.swift` —
`SHA256("TEST-ONLY PRIVATE KEYrecordIntegrity")` (single string, no space) —
then the Ed25519 public key is derived from that 32-byte
seed using the same curve family as the source implementation
(`Curve25519.Signing`, i.e. Ed25519), via Python `cryptography`
`Ed25519PrivateKey.from_private_bytes`. Results are recorded verbatim; they
were computed before being written here.

```text
test seed (hex)          = da0d947f0258c80574ba44b9a4cc560c2da09fdd11f9f20642656d4cb80c9ddf
test derived pubkey b64  = OLL1JQBKoYYj8pdThR/MpDN8xTnYOIwzxvRkLnQSu4c=
test derived pubkey hex  = 38b2f525004aa18623f29753851fcca4337cc539d8388c33c6f4642e7412bb87
test derived pubkey sha256 = 418c6cbfaaa4c3728dc4ee7cf9221b951c1407ca7b753ee2d644bcaefa51f338

production anchor pubkey b64 = +fG2YJ+YnW1RtsX8bCbukUERvSlIq4fvP7cZcs6+VMI=
production anchor pubkey hex = f9f1b6609f989d6d51b6c5fc6c26ee914111bd2948ab87ef3fb71972cebe54c2
production anchor pubkey sha256 = 8c7c011f4f1458fad4b26b0d6a12b3f37bbab5b6a10eaef46530efb0c475c4c4

byte-level comparison = NOT EQUAL
```

## 3. Source version and reproduction steps

```text
source version = implementation commit f1a6b876658e8cd7558b307a78e9da19b367ddc9;
seed derivation = SHA-256 over the exact UTF-8 bytes of
  "TEST-ONLY PRIVATE KEYrecordIntegrity";
pubkey derivation = Ed25519, raw 32-byte public key, from the seed as the
  private key (matching Curve25519.Signing.PrivateKey(rawRepresentation:));
reproduction = re-run the derivation with any Ed25519 implementation and
  compare the raw 32-byte public keys byte for byte.
```

## 4. Conclusion

```text
test-derived public key ≠ production anchor public key (byte-level, exact);
the test issuer therefore cannot produce signatures that pass the production
anchor verification; E2's UNKNOWN custody conclusion is unchanged and is now
supported by direct computation instead of a collision-probability argument.
```
