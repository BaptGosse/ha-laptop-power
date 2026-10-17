# Laptop Power

An old laptop makes a good Home Assistant OS server: it is quiet, it uses little power, and its battery
works as a built-in UPS. Two things are missing, though:

- Home Assistant does not know about the battery, so it cannot tell you about a power outage.
- After a long outage, once the battery is empty, most laptops **do not start again by themselves** when
  power comes back, and their BIOS has no "restore on AC power loss" option.

This app fixes both. During a long outage, it shuts the laptop down cleanly before the battery is empty
and schedules a wake-up through the RTC alarm. The laptop then starts by itself every 30 minutes (by
default): if power is back, Home Assistant runs again. If not, it shuts down again and tries later.

## Sensors

| Entity | Meaning |
|-|-|
| `binary_sensor.laptop_mains_power` | On when the laptop runs on mains power, off during an outage |
| `sensor.laptop_battery` | Battery charge (%) |
| `sensor.laptop_battery_health` | Current full capacity compared with the original one (%) |
| `sensor.laptop_battery_power` | Power flowing in or out of the battery (W) |
| `sensor.laptop_battery_runtime` | Estimated runtime left during an outage (min) |
| `sensor.laptop_battery_status` | `charging`, `discharging`, `full` or `not_charging` |
| `sensor.laptop_battery_cycles` | Charge cycle count, when the battery reports it |

They are updated every 30 seconds by default. Set **Sensor language** to `fr` for French names.

## Events

| Event | Data |
|-|-|
| `laptop_power_lost` | `battery_level` |
| `laptop_power_restored` | `battery_level` |
| `laptop_power_shutdown` | `battery_level`, `wake_at` (UTC), `wake_scheduled`, `dry_run` |

Example: a notification on your phone during an outage.

```yaml
automation:
  - alias: Power outage
    triggers:
      - trigger: state
        entity_id: binary_sensor.laptop_mains_power
        from: "on"
        to: "off"
    actions:
      - action: notify.mobile_app_my_phone
        data:
          message: "Power outage: Home Assistant runs on battery ({{ states('sensor.laptop_battery') }} %)"
```

## Options

| Option | Default | Meaning |
|-|-|-|
| Shutdown battery level | 15 | During an outage, clean shutdown at this battery level (%). Keep enough for a few restarts. |
| Wake-up interval | 30 | Minutes between that shutdown and the next automatic start. |
| Polling interval | 30 | Seconds between two battery readings. |
| Sensor language | en | `en` or `fr`. |
| Dry run | false | Only logs and sends `laptop_power_shutdown`, without a wake-up or a shutdown. |

A shutdown needs two low readings in a row on battery power, and never happens in the first 2 minutes
after the app starts.

## Check that your laptop wakes up from the RTC

The firmware must accept an RTC wake-up while the laptop is off. Most do, even without a BIOS option for
it. To check before relying on it, boot any Linux live USB (Fedora, Ubuntu) and run:

```
sudo rtcwake -m off -s 120
```

The laptop powers off. If it starts again by itself about 2 minutes later, this app will work.

You can then test the whole cycle: enable **Dry run**, unplug the charger and watch the log. Then disable
it, set **Shutdown battery level** high (e.g. 95) and **Wake-up interval** low (e.g. 5), and unplug the
charger again: the laptop should shut down, start again 5 minutes later, shut down again while the
charger is unplugged, and stay on once it is plugged back. Restore your settings afterwards.

## Notes

- The app reads the battery from `/sys/class/power_supply` and only needs access to `/dev/rtc0` to
  schedule the wake-up. It shuts the host down through the Supervisor.
- If the battery dies before the shutdown level (a worn battery can drop fast), the laptop has to be
  started by hand. On many laptops, opening the lid is enough.
- Home Assistant OS already ignores the lid: a closed laptop keeps running.
- Keeping a battery at 100 % all the time wears it. Some laptops support a charge limit, but it is not
  handled here.
