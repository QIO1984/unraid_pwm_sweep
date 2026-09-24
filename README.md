# pwm-sweep

A small, standalone diagnostic script for Unraid (or any Linux box with
`lm-sensors`/hwmon) that helps you find out whether your fan headers can
actually be trusted at low PWM values — **before** you configure a fan
control app to use them.

## Why this exists

Fan control apps on Unraid (fanctrlplus2, Dynamix Auto Fan Control, and
others) generally work the same way: they read a temperature, compute a PWM
value on a linear curve, and write that value to a `pwmN` file under
`/sys/class/hwmon/`. They assume that writing a lower PWM value always
results in a proportionally slower fan, and that the matching `fanN_input`
tachometer always reports the fan's real speed.

That assumption doesn't always hold. Two failure modes are common enough
to be worth checking for on any new build before you trust a fan curve:

- **A noisy or unreliable tachometer at low duty cycles.** Some fans/boards
  report erratic RPM once PWM drops below a certain point, even though the
  fan itself is running fine.
- **A firmware/EC dead zone.** Some hwmon drivers — `dell_smm` (Dell's
  System Management Mode fan interface) is a known example — don't support
  a true continuous 0-255 PWM range. Below some threshold, the firmware
  ignores your requested value and silently substitutes its own failsafe
  speed, which is often *high*, not low. From the outside this looks like
  the fan randomly jumping to near-full-speed for no reason, even though
  your fan control app is correctly computing a low PWM value and correctly
  writing it. It isn't a bug in the fan control app — the app's write is
  simply being overridden downstream, in hardware/firmware it has no
  visibility into.

Both failure modes produce the same confusing symptom: **a fan control app
that looks like it's misbehaving, ramping fans up and down for no reason,**
even when its temperature logic and PWM math are working exactly as
intended. If you've ever seen fan speed jump around and assumed the
software was buggy, this script is meant to answer, cheaply and directly:
*"is my hardware even honoring the PWM values I'm sending it?"*

## What it does

The script takes over one fan header, steps its PWM value through a fixed
set of test points from low to full, and takes several RPM samples at each
step. It prints a table so you can see, at a glance, whether the RPM
readings are:

- **Stable and roughly proportional to PWM** — your hardware is behaving
  and you can trust a fan control app's curve down to that PWM value.
- **Noisy/scattered** at a given step — the tachometer is unreliable there.
- **Pinned to an unexpected fixed value**, especially at the low end —
  a sign of a firmware dead zone (see the `dell_smm` example above).

It restores nothing on its own beyond handing the PWM line back — see
**Important** below.

## Requirements

- Root access on the Unraid box (or wherever you're running this).
- `lm-sensors` is not strictly required by the script itself, but is
  strongly recommended so you can cross-check results with `sensors` and
  identify your fan headers in the first place.
- The fan you're testing must already be controllable via a `pwmN` file
  under `/sys/class/hwmon/hwmonX/` — which is true for anything a fan
  control app like fanctrlplus2 already manages.

## Usage

The script reads the `controller=` path directly out of an existing
fanctrlplus2 `.cfg` file, so you don't need to hunt down hwmon paths by
hand if you're already using that plugin:

```bash
chmod +x pwm_sweep.sh
./pwm_sweep.sh /boot/config/plugins/fanctrlplus2/fanctrlplus2_CPU.cfg
```

Run it once per fan you want to test.

If you're not using fanctrlplus2, or want to test a header manually, open
the script and edit the `controller=` / `fan_path=` derivation directly, or
point it at a minimal `.cfg`-style file containing just:

```bash
controller="/sys/class/hwmon/hwmon2/pwm1"
```

### Via Unraid's User Scripts plugin

If you'd rather not use SSH:

1. **Settings → User Scripts → Add New Script**
2. Paste in the contents of `pwm_sweep.sh`
3. Since User Scripts doesn't pass command-line arguments through its UI,
   hardcode the cfg path near the top of the script instead of relying on
   `$1`, e.g.:
   ```bash
   cfg_file="/boot/config/plugins/fanctrlplus2/fanctrlplus2_CPU.cfg"
   ```
4. Run it in the foreground so you can watch the RPM samples live.

## Important

This script takes **manual control of the fan's PWM line** for the
duration of the sweep (roughly 75 seconds per fan, longer if you add more
test points). This means:

- Any fan control app currently managing that header will be **overridden**
  while the sweep runs.
- The script does **not** restart or re-enable your fan control app when
  it finishes — this is intentional, since the script is meant to work
  regardless of which app (if any) you use. **Manually restart your fan
  control app after the sweep completes.**
- Fan speed may be low or erratic during the sweep itself. Don't run this
  unattended on a system under real thermal load.

## Example Results

PWM PWM % RPM samples (0.5s apart)
--------------------------------------------------------------
30 11% 4720 4724 4724 4720 4720 4728
51 20% 4712 4716 4712 4716 4712 4707
62 24% 4724 4720 4724 4712 4720 4720
77 30% 799 780 772 769 769 768     **<<< Here we can see that RPM's are 
90 35% 767 767 767 767 767 767       unnecessarily fast until PWM% reached
105 41% 767 767 767 767 768 768      30%. So fan Idle, and Min Speed should
120 47% 766 766 766 766 766 766      be set at a 30% floor.
140 54% 767 768 768 767 767 767
160 62% 767 768 767 767 768 768
190 74% 766 767 767 768 767 767
220 86% 4728 4732 4724 4724 4724 4728
255 100% 4720 4716 4716 4707 4716 4716


## Reading the results

Look at the PWM column against the RPM samples for each row:

- If RPM samples at a given PWM step are tightly clustered and scale
  sensibly with PWM (higher PWM → higher RPM), that value is safe to use.
- If RPM samples are scattered/inconsistent at a step, avoid setting your
  fan curve that low — the tachometer can't be trusted there.
- If RPM is **pinned at an unexpectedly high, constant value** across a
  range of low PWM steps, and then drops to a lower, proportional value
  once PWM climbs past some point — that's the firmware dead zone pattern.
  Everything below that crossover point is being silently overridden.

## What to do with the result

**Set your fan control app's Min Speed (and Idle Speed, if it has a
separate setting) to a PWM value comfortably above wherever your sweep
showed RPM readings become stable and proportional to PWM** — not at 0,
and not at whatever your app's default happens to be. Concretely:

1. Find the lowest PWM value in your sweep where RPM was stable and
   scaled sensibly with PWM (call it `X`).
2. Set both **Min Speed** and **Idle Speed** in your fan control app to a
   value at or slightly above `X`, to leave a small safety margin in case
   the true threshold shifts slightly across reboots/BIOS updates.
3. Never set either value inside a dead zone or noisy-tach range you
   identified — the app can compute the "correct" PWM there all day, and
   your hardware still won't do what it's told.

This is a one-time check per fan header per machine — once you know where
the safe floor is, you're done; you don't need to re-run this unless you
change hardware, BIOS fan settings, or swap the fan itself.
