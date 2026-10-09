#!/usr/bin/env python3
"""Kill this process inside an uncommitted demand transaction."""
from __future__ import annotations

import argparse
import os
import signal

from carrier_loop import CarrierInformationLoop


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", required=True)
    parser.add_argument("--demand-id", required=True)
    parser.add_argument("--crash-item", required=True)
    args = parser.parse_args()

    loop = CarrierInformationLoop.open(args.database)

    def calculator(item_id: str, source_payload: dict, dependencies: dict) -> dict:
        if item_id == args.crash_item:
            os.kill(os.getpid(), signal.SIGKILL)
        return {"value": source_payload["value"]}

    loop.execute_demand(
        args.demand_id,
        "crash-worker-advance",
        calculator,
        evaluated_at_utc="2026-10-09T00:06:00Z",
    )
    loop.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
