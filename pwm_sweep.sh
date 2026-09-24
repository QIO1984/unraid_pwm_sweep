#!/bin/bash
# pwm_sweep.sh - Bypass fanctrlplus2 entirely and manually step a fan's PWM
# through a range of values, reading RPM at each step, to find the point
# where the tachometer reading becomes stable/trustworthy.
#
# Usage:
#   ./pwm_sweep.sh /boot/config/plugins/fanctrlplus2/fanctrlplus2_CPU.cfg
#   ./pwm_sweep.sh /boot/config/plugins/fanctrlplus2/fanctrlplus2_Exhaust.cfg
#
# IMPORTANT: this takes manual control of the fan's PWM line while it runs,
# which means it will override/pause any fan-control app you have running
# (fanctrlplus2, Dynamix Auto Fan Control, a custom script, etc) for the
# ~75 second duration of the sweep. Restart or re-enable that app once the
# sweep finishes - this script does not do that for you, since it's meant
# to work standalone regardless of which fan-control app (if any) you use.

set -u

cfg_file="${1:-}" #change to fan plugin cfg path. ex: cfg_file="/boot/config/plugins/fanctrlplus2/fanctrlplus2_CPU.cfg" 
if [[ -z "$cfg_file" || ! -f "$cfg_file" ]]; then
  echo "Usage: $0 <path-to-fanctrlplus2-fan-cfg-file>"
  echo "e.g.:  $0 /boot/config/plugins/fanctrlplus2/fanctrlplus2_CPU.cfg"
  exit 1
fi

# Reuse the exact same var names the plugin's own cfg files define.
source "$cfg_file"

if [[ -z "${controller:-}" || ! -e "$controller" ]]; then
  echo "Could not find a valid 'controller' path in $cfg_file"
  exit 1
fi

# Derive the matching fanN_input path, same logic as fanctrlplus2_loop.sh.
if [[ "$controller" =~ pwm([0-9]+)$ ]]; then
  fan_index="${BASH_REMATCH[1]}"
  fan_path="$(dirname "$controller")/fan${fan_index}_input"
else
  echo "Could not derive fan tach path from controller: $controller"
  exit 1
fi

controller_enable="${controller}_enable"

echo "Controller : $controller"
echo "Fan input  : $fan_path"
echo "Enable     : $controller_enable"
echo

# Switch this one fan into manual mode for the duration of the sweep.
[[ -f "$controller_enable" ]] && echo 1 > "$controller_enable"

# PWM values to test (0-255 scale). Adjust/add points if you want finer
# resolution around wherever things start looking shaky.
pwm_steps=(30 51 62 77 90 105 120 140 160 190 220 255)

# How many RPM samples to take per PWM step, and delay between them.
samples_per_step=6
sample_delay=0.5
# Let the fan physically settle after each PWM change before sampling.
settle_delay=3

printf "%-6s %-10s %s\n" "PWM" "PWM %" "RPM samples (0.5s apart)"
printf "%s\n" "--------------------------------------------------------------"

for pwm_val in "${pwm_steps[@]}"; do
  echo "$pwm_val" > "$controller"
  sleep "$settle_delay"

  readings=()
  for ((i = 0; i < samples_per_step; i++)); do
    r=$(cat "$fan_path" 2>/dev/null)
    readings+=("${r:-?}")
    sleep "$sample_delay"
  done

  pct=$(( pwm_val * 100 / 255 ))
  printf "%-6s %-10s %s\n" "$pwm_val" "${pct}%" "${readings[*]}"
done

echo
echo "Sweep done."
echo "This script does not restart any fan-control app for you - if you run"
echo "one (fanctrlplus2, Dynamix Auto Fan Control, etc), restart/re-enable it"
echo "now so it resumes managing this fan."
echo
echo "Look for the PWM value(s) where RPM samples stop swinging wildly or"
echo "'sticking' at an unexpected speed. See README.md for how to read this."
