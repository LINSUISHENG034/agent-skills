# Bluetooth and Audio Diagnostics

Use this reference for Bluetooth device state, audio sink visibility, and playback routing on the deployment host.

## Single device info

For a direct request like "run `bluetoothctl info <MAC>` and tell me the result", run the exact command first:

```bash
bluetoothctl info <MAC>
```

Useful fields to extract:

- `Name`
- `Alias`
- `Paired`
- `Trusted`
- `Connected`
- `Blocked`

## Bluetooth layer

```bash
bluetoothctl devices
bluetoothctl devices Connected
bluetoothctl show
bluetoothctl info <MAC>
systemctl status bluetooth --no-pager
journalctl -u bluetooth -n 80 --no-pager
```

## PipeWire / PulseAudio layer

```bash
pactl info
pactl list short cards
pactl list short sinks
wpctl status
wpctl inspect @DEFAULT_AUDIO_SINK@
systemctl --user status wireplumber pipewire pipewire-pulse --no-pager
journalctl --user -u wireplumber -u pipewire -u pipewire-pulse -n 120 --no-pager
```

## Interpreting evidence

- `Connected: yes` in `bluetoothctl info` means BlueZ sees the device connection.
- If Bluetooth is connected but no `bluez_output...` sink exists, the audio stack has not exposed a usable sink.
- If a sink exists but playback still fails, the likely issue is routing, mute, profile, or output path.

## Default answer pattern for direct Bluetooth queries

For "can you run `bluetoothctl info <MAC>` and tell me the result":

1. Run the exact command.
2. Report the important fields.
3. Include a short raw excerpt if helpful.
4. Do not expand into generic Bluetooth troubleshooting unless the user asks for diagnosis.
