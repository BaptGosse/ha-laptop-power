# Laptop Power for Home Assistant OS

A Home Assistant app for Home Assistant OS running on a laptop:

- **battery sensors**: mains power, charge, health, power, runtime;
- **power outage events**, to get notified when the house loses power and when it comes back;
- **automatic restart after a long outage**: before the battery is empty, a clean shutdown with an RTC
  wake-up, so the laptop starts again by itself once power is back. This works even when the BIOS has no
  "restore on AC power loss" option.

See the [documentation](laptop_power/DOCS.md) for details, and how to check that your laptop supports the
RTC wake-up.

## Installation

1. In Home Assistant, go to **Settings → Apps → App store**, then **⋮ → Repositories**, and add
   `https://github.com/BaptGosse/ha-laptop-power`.
2. Install **Laptop Power** and start it.
3. The sensors appear within a minute (`binary_sensor.laptop_mains_power`, `sensor.laptop_battery`…).

Only `amd64` is supported, since that is what laptops run.

## License

MIT
