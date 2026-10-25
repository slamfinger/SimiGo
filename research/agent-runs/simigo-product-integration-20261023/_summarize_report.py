import json,sys
d=json.load(open(sys.argv[1]))
print("issueCount=", d["issueCount"], "schemaVersion=", d["schemaVersion"],
      "modelsDiscovered=", d["modelsDiscovered"], "workFilesIndexed=", d["workFilesIndexed"])
for s in d["steps"]:
    print("  step", s["id"], "->", s["status"], "|", s["detail"][:70])
