import importlib.util, sys, unittest
from pathlib import Path

PATH=Path(__file__).resolve().parents[1]/"declarative_result_contract.py"
spec=importlib.util.spec_from_file_location("declarative_result_contract", PATH)
mod=importlib.util.module_from_spec(spec); sys.modules[spec.name]=mod; spec.loader.exec_module(mod)

CONTRACT={
  "schema_version":"simigo.result-contract/v1",
  "fields":{
    "origin_code":{"pattern":"^ORIGIN=([A-Z]+)$","capture_group":1,"type":"string"},
    "destination_code":{"pattern":"^DEST=([A-Z]+)$","capture_group":1,"type":"string"},
    "route_key":{"pattern":"^ROUTE=([A-Z]+>[A-Z]+)$","capture_group":1,"type":"string"},
    "priority":{"pattern":"^PRIORITY=([0-9]+)$","capture_group":1,"type":"integer","minimum":0,"maximum":9}
  },
  "constraints":[
    {"kind":"equals_binding","field":"origin_code","binding":"origin_code"},
    {"kind":"equals_binding","field":"destination_code","binding":"destination_code"},
    {"kind":"equals_binding","field":"priority","binding":"priority"},
    {"kind":"concat","field":"route_key","parts":["origin_code","destination_code"],"separator":">"}
  ]
}
TEXT="ORIGIN=NORTH\nDEST=EAST\nROUTE=NORTH>EAST\nPRIORITY=5\n"
BINDINGS={"origin_code":"NORTH","destination_code":"EAST","priority":5}

class DeclarativeContractTests(unittest.TestCase):
    def test_valid_contract_is_id_independent(self):
        # Runtime IDs are intentionally opaque metadata outside the validator API.
        item_ids=("J-run-a-opaque-u1", "J-run-b-unseen-u1")
        outputs={item_id: mod.validate_result_text(TEXT, CONTRACT, BINDINGS) for item_id in item_ids}
        self.assertEqual(outputs[item_ids[0]]["values"], outputs[item_ids[1]]["values"])
        self.assertEqual(outputs[item_ids[0]]["validation_status"], "VALID")
        self.assertEqual(outputs[item_ids[0]]["values"]["route_key"], "NORTH>EAST")
    def test_missing_required_field_rejects(self):
        with self.assertRaisesRegex(mod.ContractError,"PRODUCER_RESULT_FIELD_MISSING"):
            mod.validate_result_text("ORIGIN=NORTH\nDEST=EAST\nPRIORITY=5",CONTRACT,BINDINGS)
    def test_binding_mismatch_rejects(self):
        with self.assertRaisesRegex(mod.ContractError,"PRODUCER_RESULT_BINDING_MISMATCH"):
            mod.validate_result_text(TEXT,CONTRACT,{**BINDINGS,"priority":4})
    def test_derived_field_mismatch_rejects(self):
        with self.assertRaisesRegex(mod.ContractError,"PRODUCER_RESULT_DERIVATION_MISMATCH"):
            mod.validate_result_text(TEXT.replace("NORTH>EAST","NORTH>WEST"),CONTRACT,BINDINGS)
    def test_unknown_version_fails_closed(self):
        with self.assertRaisesRegex(mod.ContractError,"CONTRACT_UNKNOWN_SCHEMA_VERSION"):
            mod.validate_result_text(TEXT,{**CONTRACT,"schema_version":"simigo.result-contract/v999"},BINDINGS)
    def test_unknown_constraint_fails_closed(self):
        with self.assertRaisesRegex(mod.ContractError,"CONTRACT_UNKNOWN_CONSTRAINT"):
            mod.validate_result_text(TEXT,{**CONTRACT,"constraints":[{"kind":"magic","field":"route_key"}]},BINDINGS)
    def test_ambiguous_field_rejects_by_default(self):
        with self.assertRaisesRegex(mod.ContractError,"CONTRACT_AMBIGUOUS_FIELD"):
            mod.validate_result_text(TEXT+"PRIORITY=5\n",CONTRACT,BINDINGS)
    def test_declared_first_match_policy_is_explicit(self):
        contract={**CONTRACT,"fields":{**CONTRACT["fields"],"priority":{**CONTRACT["fields"]["priority"],"match_policy":"first"}}}
        result=mod.validate_result_text(TEXT+"PRIORITY=9\n",contract,BINDINGS)
        self.assertEqual(result["values"]["priority"],5)
    def test_integer_range_is_enforced(self):
        with self.assertRaisesRegex(mod.ContractError,"CONTRACT_RANGE_VIOLATION"):
            mod.validate_result_text(TEXT.replace("PRIORITY=5","PRIORITY=15"),CONTRACT,BINDINGS)

if __name__=="__main__": unittest.main()
