"""Execution gate; decision replay is not authorized in preparation."""
from __future__ import annotations


def main() -> int:
    print("NOT_AUTHORIZED_D002_EXPERIMENT")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
