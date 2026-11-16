import unittest
from types import SimpleNamespace

from bridge import apply_and_read, read_device, update_device
from pybmap.errors import BmapTimeoutError


class Headphones:
    device_info = {"name": "QuietComfort 35", "codename": "baywolf"}
    level = "high"

    def has_feature(self, name):
        return name in {"anr", "sidetone"}

    def battery(self):
        return 74

    def anr(self):
        return self.level

    def set_anr(self, value):
        self.level = value

    def sidetone(self):
        raise BmapTimeoutError("No response from device")


class BridgeTests(unittest.TestCase):
    def test_update_reads_only_changed_setting(self):
        device = Headphones()
        previous = read_device(device)
        device.battery = lambda: self.fail("read battery during ANR update")
        device.sidetone = lambda: self.fail("read sidetone during ANR update")
        snapshot, warning = apply_and_read(device, "anr", "low", previous)
        self.assertEqual(snapshot["anr"], "low")
        self.assertEqual(snapshot["battery"], 74)
        self.assertEqual(snapshot["unavailable"], ["Sidetone"])
        self.assertIsNone(warning)

    def test_eq_verification_reuses_single_readback(self):
        device = Headphones()
        device.has_feature = lambda name: name == "eq"
        device.set_eq = lambda *_: None
        reads = iter([[SimpleNamespace(band_id=i, name=str(i), min_val=-10,
                                       max_val=10, current=0) for i in range(3)]])
        device.eq = lambda: next(reads)
        snapshot, warning = apply_and_read(device, "eq", [1, 0, 0], {"battery": 74})
        self.assertEqual([band["value"] for band in snapshot["eq"]], [0, 0, 0])
        self.assertIn("confirm", warning)

    def test_qc35_reports_only_available_controls_and_read_failures(self):
        snapshot = read_device(Headphones())
        self.assertEqual(snapshot["battery"], 74)
        self.assertEqual(snapshot["anr"], "high")
        self.assertNotIn("eq", snapshot)
        self.assertIsNone(snapshot["sidetone"])
        self.assertEqual(snapshot["unavailable"], ["Sidetone"])

    def test_anr_is_read_back_after_update(self):
        device = Headphones()
        update_device(device, "anr", "low")
        self.assertEqual(read_device(device)["anr"], "low")

    def test_eq_uses_band_ids_and_preserves_hardware_limits(self):
        device = Headphones()
        device.has_feature = lambda name: name == "eq"
        device.eq = lambda: [
            SimpleNamespace(band_id=i, name=name, min_val=-6, max_val=8, current=i)
            for i, name in ((2, "Treble"), (0, "Bass"), (1, "Mid"))
        ]
        self.assertEqual(read_device(device)["eq"], [
            {"id": i, "name": name, "minimum": -6, "maximum": 8, "value": i}
            for i, name in enumerate(("Bass", "Mid", "Treble"))
        ])

    def test_unsupported_control_is_rejected_before_write(self):
        with self.assertRaisesRegex(ValueError, "unavailable"):
            update_device(Headphones(), "eq", [0, 0, 0])


if __name__ == "__main__":
    unittest.main()
