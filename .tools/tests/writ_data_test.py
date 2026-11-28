import importlib.util
import sys
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("writ_data", root / "scripts/writ-data.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Tips:
    fetch = False

    def get(self, item_id):
        return {"name": "Waylaid Crate: Artisan Textiles", "tooltip": "<br />- 40 Runecloth"}

    def name(self, item_id, fallback):
        return fallback


cases = [(248698, "gathered", 5, True), (248699, "gathered", 20, False), (248711, "crafted", 40, False)]
for item_id, kind, favor, override in cases:
    source = [{"item_id": str(item_id), "tier": "artisan", "kind": kind}]
    with patch.object(module, "tsv_rows", return_value=source), \
            patch.object(module, "resolve_names", return_value={"Runecloth": 14047}):
        row = module.build_crates(Path("."), Tips())[0]
        assert f'favor = {favor}, confirmed = true' in row, row
        assert ('rewardOverride = true' in row) == override, row

print("writ data generator test passed")
