"""JSON interface from the macOS app to the existing Python Bluetooth backend."""

import json
import sys

import pybmap
from pybmap.devices import get_device


def read_device(device):
    snapshot = {
        "model": device.device_info["name"],
        "battery": device.battery(),
        "unavailable": [],
    }

    def read(key, label, getter):
        try:
            value = getter()
            if value is not None:
                snapshot[key] = value
                return
        except pybmap.BmapError:
            pass
        snapshot[key] = None
        snapshot["unavailable"].append(label)

    features = {
        "product_name": ("name", "Device name", "name"),
        "firmware": ("firmware", "Firmware version", "firmware"),
        "anr": ("anr", "Noise cancellation", "anr"),
        "sidetone": ("sidetone", "Sidetone", "sidetone"),
        "multipoint": ("multipoint", "Multipoint", "multipoint"),
        "auto_pause": ("autoPause", "Auto-pause", "auto_pause"),
        "auto_answer": ("autoAnswer", "Auto-answer", "auto_answer"),
    }
    for feature, (key, label, method) in features.items():
        if device.has_feature(feature):
            read(key, label, getattr(device, method))

    if device.has_feature("voice_prompts"):
        read("prompts", "Voice prompts", lambda: device.prompts()[0])
    if device.has_feature("current_mode"):
        modes = {entry["idx"]: name for name, entry in device.preset_modes.items()}
        if device.has_feature("get_all_modes"):
            read("profiles", "Custom modes", lambda: [
                {"id": p.mode_idx, "name": p.name, "command": p.name}
                for p in device.profiles()
                if p.editable and p.configured and p.name and p.mode_idx not in modes
            ])
        snapshot["profiles"] = [
            {"id": idx, "name": name.capitalize(), "command": name}
            for idx, name in sorted(modes.items())
        ] + (snapshot.get("profiles") or [])
        read("mode", "Active mode", device.mode_idx)
    if device.has_feature("audio_settings"):
        read("audio", "Audio settings", lambda: device.audio_settings()._asdict())
    if device.has_feature("eq"):
        def read_eq():
            bands = sorted(device.eq(), key=lambda band: band.band_id)
            if [band.band_id for band in bands] != [0, 1, 2]:
                return None
            return [
                {"id": b.band_id, "name": b.name, "minimum": b.min_val,
                 "maximum": b.max_val, "value": b.current}
                for b in bands
            ]
        read("eq", "Equalizer", read_eq)
    return snapshot


def update_device(device, control, value):
    controls = {
        "mode": ("current_mode", "set_mode"),
        "anr": ("anr", "set_anr"),
        "noise": ("audio_settings", "set_cnc"),
        "anc": ("audio_settings", "set_anc"),
        "wind": ("audio_settings", "set_wind"),
        "spatial": ("audio_settings", "set_spatial"),
        "eq": ("eq", "set_eq"),
        "sidetone": ("sidetone", "set_sidetone"),
        "multipoint": ("multipoint", "set_multipoint"),
        "autoPause": ("auto_pause", "set_auto_pause"),
        "autoAnswer": ("auto_answer", "set_auto_answer"),
        "prompts": ("voice_prompts", "set_prompts"),
    }
    if control not in controls:
        raise ValueError("Unknown headphone control")
    feature, method = controls[control]
    if not device.has_feature(feature):
        raise ValueError("This control is unavailable on the connected headphones")
    if control == "eq":
        if len(value) != 3 or any(type(v) is not int or not -10 <= v <= 10 for v in value):
            raise ValueError("Expected three EQ values from −10 to +10")
        device.set_eq(*value)
        # The library's band writes do not check individual acknowledgments.
        bands = sorted(device.eq(), key=lambda band: band.band_id)
        if [band.band_id for band in bands] != [0, 1, 2] or [b.current for b in bands] != value:
            raise pybmap.BmapError("The headphones did not apply every EQ value.")
    else:
        getattr(device, method)(value)


def main():
    try:
        request = json.loads(sys.argv[1])
        if request.get("check"):
            print(json.dumps({"ready": True}))
            return
        address, model = request.get("address"), request.get("deviceType")
        if not address:
            address, model = pybmap.find_bmap_device()
            if not address:
                raise pybmap.BmapNotFoundError(
                    "Connect your QuietComfort headphones in System Settings → Bluetooth, then try again."
                )
        get_device(model)  # Validate the model before opening an RFCOMM channel.
        with pybmap.connect(mac=address, device_type=model) as device:
            warning = None
            if request.get("control"):
                try:
                    update_device(device, request["control"], request["value"])
                except (pybmap.BmapError, ValueError) as error:
                    warning = str(error)
            snapshot = read_device(device)
        print(json.dumps({"snapshot": snapshot, "address": address,
                          "deviceType": model, "warning": warning}))
    except Exception as error:
        print(json.dumps({"error": str(error) or type(error).__name__}))


if __name__ == "__main__":
    main()
