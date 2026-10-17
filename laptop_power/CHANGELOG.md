# Changelog

## 0.1.1

- Fix: the app stopped at boot, because Home Assistant is not up yet when it starts. Calls to Home Assistant
  are now retried at the next reading, and missing battery files no longer stop it.

## 0.1.0

- Battery, mains power, battery health, power, runtime, status and cycle sensors.
- `laptop_power_lost`, `laptop_power_restored` and `laptop_power_shutdown` events.
- Clean shutdown at a battery level during an outage, with an RTC wake-up to restart once power is back.
