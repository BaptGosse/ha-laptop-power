#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# Laptop Power: battery sensors and power outage events for Home Assistant OS running on a laptop.
# During a long outage it shuts down cleanly before the battery is empty and schedules an RTC wake-up,
# so the laptop starts again by itself once power is back.
# bashio runs with errexit and nounset: every read or call that may fail must not stop the loop.

LEVEL=$(bashio::config 'shutdown_battery_level')
WAKE_MINUTES=$(bashio::config 'wake_interval')
POLL=$(bashio::config 'poll_interval')
LANGUAGE=$(bashio::config 'language')
DRY_RUN=$(bashio::config 'dry_run')
STARTUP_GRACE=${STARTUP_GRACE:-120}  # no shutdown in the first 2 minutes: Home Assistant starts and reports the outage
POWER_SUPPLY_DIR=${POWER_SUPPLY_DIR:-/sys/class/power_supply}  # overridable for tests
CORE=http://supervisor/core/api

declare -A NAMES_EN=(
  [ac]="Laptop mains power" [battery]="Laptop battery" [health]="Laptop battery health"
  [power]="Laptop battery power" [runtime]="Laptop battery runtime" [status]="Laptop battery status"
  [cycles]="Laptop battery cycles"
)
declare -A NAMES_FR=(
  [ac]="Portable : secteur" [battery]="Portable : batterie" [health]="Portable : santé de la batterie"
  [power]="Portable : puissance de la batterie" [runtime]="Portable : autonomie restante"
  [status]="Portable : état de la batterie" [cycles]="Portable : cycles de la batterie"
)
name() {
  if [ "$LANGUAGE" = fr ]; then echo "${NAMES_FR[$1]}"; else echo "${NAMES_EN[$1]}"; fi
}

# Power supplies: the first mains adapter and the first system battery (not a mouse or keyboard battery)
find_supply() {
  local d
  for d in "$POWER_SUPPLY_DIR"/*; do
    [ "$(cat "$d/type" 2>/dev/null)" = "$1" ] || continue
    [ "$(cat "$d/scope" 2>/dev/null)" = Device ] && continue
    echo "$d"
    return
  done
}
AC=$(find_supply Mains)
BAT=$(find_supply Battery)
if [ -z "$BAT" ]; then
  bashio::exit.nok "No laptop battery found in ${POWER_SUPPLY_DIR}: nothing to monitor."
fi
val() { cat "$BAT/$1" 2>/dev/null || true; }

read_state() {
  capacity=$(val capacity)
  status=$(val status)
  if [ -n "$AC" ]; then
    on_mains=$(cat "$AC/online" 2>/dev/null || true)
  elif [ "$status" = Discharging ]; then
    on_mains=0
  else
    on_mains=1
  fi
  # energy_* (µWh) and power_now (µW), or charge_* (µAh) and current_now (µA) on some batteries
  local now full design rate
  now=$(val energy_now); full=$(val energy_full); design=$(val energy_full_design); rate=$(val power_now)
  if [ -z "$now" ]; then
    now=$(val charge_now); full=$(val charge_full); design=$(val charge_full_design); rate=$(val current_now)
  fi
  health=$(awk -v f="${full:-0}" -v d="${design:-0}" 'BEGIN { if (d > 0) printf "%d", 100 * f / d }')
  power_w=""
  if [ -n "$(val power_now)" ]; then
    power_w=$(awk -v p="${rate#-}" 'BEGIN { printf "%.1f", p / 1e6 }')
  elif [ -n "$(val voltage_now)" ]; then
    power_w=$(awk -v i="${rate#-}" -v u="$(val voltage_now)" 'BEGIN { printf "%.1f", i * u / 1e12 }')
  fi
  runtime=""
  if [ "$on_mains" = 0 ] && [ "${rate#-}" -gt 0 ] 2>/dev/null; then
    runtime=$(awk -v n="${now:-0}" -v r="${rate#-}" 'BEGIN { printf "%d", 60 * n / r }')
  fi
  cycles=$(val cycle_count)
}

# Home Assistant may not be up yet (the app starts before it at boot): a failed call is retried at the next poll
post_state() {  # entity_id, state, attributes (JSON)
  curl -fsS -m 10 -X POST -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" -H "Content-Type: application/json" \
    -d "$(jq -nc --arg s "$2" --argjson a "$3" '{state: $s, attributes: $a}')" "$CORE/states/$1" >/dev/null 2>&1 || true
}
fire_event() {  # event_type, data (JSON)
  curl -fsS -m 10 -X POST -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" -H "Content-Type: application/json" \
    -d "$2" "$CORE/events/$1" >/dev/null 2>&1 || true
}
attrs() {  # key, unit, device_class, state_class, icon
  jq -nc --arg n "$(name "$1")" --arg u "$2" --arg dc "$3" --arg sc "$4" --arg i "$5" \
    '{friendly_name: $n} + (if $u != "" then {unit_of_measurement: $u} else {} end)
     + (if $dc != "" then {device_class: $dc} else {} end)
     + (if $sc != "" then {state_class: $sc} else {} end) + (if $i != "" then {icon: $i} else {} end)'
}

publish() {
  post_state binary_sensor.laptop_mains_power "$([ "$on_mains" = 1 ] && echo on || echo off)" "$(attrs ac "" power "" "")"
  post_state sensor.laptop_battery "${capacity:-unknown}" "$(attrs battery % battery measurement "")"
  post_state sensor.laptop_battery_health "${health:-unknown}" "$(attrs health % "" measurement mdi:battery-heart-variant)"
  post_state sensor.laptop_battery_power "${power_w:-unknown}" "$(attrs power W power measurement "")"
  post_state sensor.laptop_battery_runtime "${runtime:-unknown}" "$(attrs runtime min duration "" mdi:timer-sand)"
  post_state sensor.laptop_battery_status "$(echo "${status:-unknown}" | tr 'A-Z ' 'a-z_')" "$(attrs status "" "" "" mdi:battery-sync)"
  post_state sensor.laptop_battery_cycles "${cycles:-unknown}" "$(attrs cycles "" "" total_increasing mdi:battery-sync-outline)"
}

shutdown_with_wake() {
  local wake_at scheduled=false
  wake_at=$(date -u -d "@$(($(date +%s) + WAKE_MINUTES * 60))" +%Y-%m-%dT%H:%M:%SZ)
  if bashio::var.true "$DRY_RUN"; then
    bashio::log.warning "Dry run: battery at ${capacity}% on battery power, would shut down and wake up at ${wake_at}"
    fire_event laptop_power_shutdown "$(jq -nc --argjson l "$capacity" --arg w "$wake_at" \
      '{battery_level: $l, wake_at: $w, wake_scheduled: false, dry_run: true}')"
    return
  fi
  bashio::log.warning "Battery at ${capacity}% on battery power: shutting down, wake-up at ${wake_at}"
  if rtcwake -d rtc0 -m no -s $((WAKE_MINUTES * 60)); then
    scheduled=true
  else
    bashio::log.error "Could not schedule the wake-up: the laptop will stay off until it is started by hand"
  fi
  fire_event laptop_power_shutdown "$(jq -nc --argjson l "$capacity" --arg w "$wake_at" --argjson s "$scheduled" \
    '{battery_level: $l, wake_at: $w, wake_scheduled: $s, dry_run: false}')"
  sleep 15  # lets Home Assistant send its notification
  bashio::host.shutdown || bashio::log.error "The Supervisor refused the shutdown"
  sleep infinity
}

read_state
bashio::log.info "Battery: ${BAT##*/}, mains adapter: ${AC##*/}. Health ${health}%, ${cycles:-?} cycles."
bashio::log.info "Shutdown at ${LEVEL}% during an outage, wake-up every ${WAKE_MINUTES} min, dry run: ${DRY_RUN}."
if [ "$on_mains" = 1 ] && ! bashio::var.true "$DRY_RUN"; then
  rtcwake -d rtc0 -m disable >/dev/null 2>&1 || true  # power is back: drop any wake-up left from an outage
fi

started=$(date +%s)
previous=""
low_polls=0
acted=false
while true; do
  read_state
  publish
  if [ -n "$previous" ] && [ "$on_mains" != "$previous" ]; then
    if [ "$on_mains" = 0 ]; then
      bashio::log.warning "Power outage: running on battery (${capacity}%)"
      fire_event laptop_power_lost "$(jq -nc --arg l "$capacity" '{battery_level: ($l | tonumber? // null)}')"
    else
      bashio::log.info "Power is back (battery ${capacity}%)"
      fire_event laptop_power_restored "$(jq -nc --arg l "$capacity" '{battery_level: ($l | tonumber? // null)}')"
    fi
  fi
  previous=$on_mains
  if [ "$on_mains" = 0 ] && [[ "$capacity" =~ ^[0-9]+$ ]] && [ "$capacity" -le "$LEVEL" ]; then
    low_polls=$((low_polls + 1))
  else
    low_polls=0
    acted=false
  fi
  # two readings in a row, so a short glitch never shuts the laptop down
  if [ "$low_polls" -ge 2 ] && [ $(($(date +%s) - started)) -ge "$STARTUP_GRACE" ] && [ "$acted" = false ]; then
    acted=true
    shutdown_with_wake
  fi
  sleep "$POLL"
done
