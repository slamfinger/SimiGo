# SimiGo Integrated ES–PALACE non-D002 validation authorization acceptance

> **Status:** AUTHORIZED — ONE RUN
> **Ruling date:** 2026-10-10
> **Ruling authority:** Human independent review
> **Request document SHA256:** `82a2f5cf030bfd5acb61a3f37866e28e70ca9eb8c206bffb599e3f2d692fd5f9`
> **Authorized request:** `INTEGRATED-ES-PALACE-NON-D002-VALIDATION-AUTHORIZATION-REQUEST-V1.0`

## 1. Ruling

```text
Authorization Request v1.0 = ACCEPT;
authorized executions = 1;
cases = the seven immutable fixture-package cases;
Run Manifest creation = authorized within this work order;
isolated stdlib validation runner = authorized;
fresh-entry validation = authorized;
automatic rerun / repair / second run = FORBIDDEN;
result = VALIDATION_PASS or VALIDATION_FAIL only.
```

The authorized object is an isolated SimiGo Execution State + PALACE
Information Space integration validation. It is not production authorization
and does not establish Integrated SimiGo full production proof.

## 2. Binding at ruling

```text
canonical base = 6e2589b88578ff8a4b3ee125d013d167fcebb4b2;
fixture manifest SHA256 =
  998bbbb77868cb4b36ddced1aa544a65da17a5bf4b1ecfde5b866ae8833ecc05;
fixture checksum list SHA256 =
  a08ce9373c43dd1c01ba911ddf27e5cabed189d740f83b99475ec13bbb4b9c19;
isolation proof SHA256 =
  9d94634446fa17749a5863382bb6b8640338ee09bf206fcd166fb23a818505e9;
missing-item record SHA256 =
  c98685e70b60cfe6e755069898c9dd1a4626e85ee1a18a1d6614e72f2678b543;
preparation self-check SHA256 =
  43c275b616504322422eb8a741402572e94ae3b43f332586161546d3dc273e9b;
preparation tool SHA256 =
  13e814fc77cf9f87a6320e421c3e343305afb0b0f929cbce95823aa83a1824df;
sealed PALACE snapshot SHA256 =
  8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444.
```

## 3. Continuing boundaries

```text
Pilot v5 SQLite busy revision = ACCEPT / CLOSED;
Fixture Preparation = COMPLETE;
non-D002 integration validation = AUTHORIZED — ONE RUN;
production deployment = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED;
canonical PALACE / Information Space mutation = FORBIDDEN;
D-002 rerun / repair-run = FORBIDDEN;
network access = FORBIDDEN;
model participation in authority path = FORBIDDEN.
```
