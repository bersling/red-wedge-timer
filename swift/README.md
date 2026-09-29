# Red Wedge Timer (macOS)

A visual countdown for kids: turn the dial, the red disk shrinks as time runs
out, and it beeps — repeatedly — when it hits zero.

## Build & run

```sh
./build.sh                      # produces "Red Wedge Timer.app" here
open "Red Wedge Timer.app"      # or copy it to /Applications
```

Needs only the Xcode command line tools (`swiftc`). No packages, no Xcode project.

## How it works

- **Set the time** — drag the knob on the red disk, or anywhere on the dial (1–60 min, one-minute steps), tap a preset,
  or use −/+. Setting a length makes no sound.
- **Run it** — Start / Pause, `Space` toggles, `Esc` goes back to the start.
- **The sound** — pick from Beeps, Chime, Cuckoo, Marimba, Bell or Buzzer in the
  dropdown under the beep lengths. Every one is synthesised from sine partials at
  runtime, so the app ships no audio files and licenses nothing.
- **Beeping** — the chosen pattern every 1.4 s, with a Dock bounce on each
  repeat. How long it keeps that up is a choice: **Off**, **1s** (one pattern),
  **10s**, **1min**, or **On** (until someone presses "Stop the beeping"). A
  single soft tone warns at one minute left, unless beeping is off; nothing else
  makes a sound.
- **The dial** — numerals sit *outside* the red disk so they stay readable at all
  times; they climb clockwise, so the disk's edge points at the minutes left.

Tones are synthesised at runtime (`AVAudioEngine`), so there are no sound assets.

## Files

| file | what's in it |
| --- | --- |
| `Sources/RedWedgeTimerApp.swift` | app + window |
| `Sources/TimerScreen.swift` | layout, presets, controls |
| `Sources/DialView.swift` | the dial (Canvas drawing + drag-to-set) |
| `Sources/TimerModel.swift` | countdown, alarm repetition |
| `Sources/Beeper.swift` | tone synthesis |
| `Sources/Palette.swift` | light/dark colours |

The earlier browser version is `../index.html`.
