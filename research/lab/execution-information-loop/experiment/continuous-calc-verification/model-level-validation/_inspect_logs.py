#!/usr/bin/env python3
import json, sys

arm = sys.argv[1]
path = f"logs/{arm}.jsonl"
with open(path, encoding="utf-8") as f:
    for i, line in enumerate(f, 1):
        obj = json.loads(line)
        elt = obj.get("elt")
        # show the key discriminating fields per event type
        if elt == "invalidate-settlement":
            print(f"{i:>2} {elt}: invalidated={obj.get('invalidated_item_ids')} reason={obj.get('reason')} include_dependents={obj.get('include_dependents')}")
        elif elt == "update-source":
            print(f"{i:>2} {elt}: unit={obj.get('unit')} version={obj.get('source_version')}")
        elif elt in ("recompute-after-invalidation", "diamond-recompute"):
            print(f"{i:>2} {elt}:")
            for k, v in obj.items():
                if k not in ("elt", "_t"):
                    s = str(v)
                    print(f"     {k} = {s[:160]}")
        elif elt == "execute-demand":
            print(f"{i:>2} {elt}: state={obj.get('state')} advanced={obj.get('advanced')} computed={obj.get('computed')} reused={obj.get('reused')}")
        elif elt == "diamond-invalidate":
            print(f"{i:>2} {elt}: invalidated={obj.get('invalidated_item_ids')}")
        elif elt in ("settle-before-invalidation", "diamond-settle-before"):
            print(f"{i:>2} {elt}: settle={obj.get('settle')}")
        else:
            print(f"{i:>2} {elt}")
