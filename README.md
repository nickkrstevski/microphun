# Microphun

A small native macOS menu bar voice changer and soundboard. Start audio, pick a voice, and adjust pitch, reverb, and modulation while you talk. Click the waveform in the menu bar to hide or reopen the controls. Right-click it to stop audio or quit.

## Try it

1. Open **Microphun.app** and select **Routing**.
2. Pick your microphone. For pads alone, choose **Soundboard only**.
3. For a private audition, switch off **Send to calls**, enable **Monitor voice**, and pick headphones. **Test monitor** plays a short two-note tone only on the selected output.
4. Click **Start audio**. Allow microphone access when macOS asks. Try **Cave troll**, **Helium**, **Tin bot**, **Sea legs**, **8-bit**, or **Houston radio**. **Clean** restores the dry voice.
5. Open **Soundboard** and click a pad. Click it again to stop it, or click another pad to replace it. An idle pad starts audio using the current input and routes. **Import** copies an audio clip up to two minutes long to your local sound library.

## Use in a call

Enable **Send to calls** and choose **Microphun Mic** (or **BlackHole 2ch** for the alternate route). Select the same microphone in the receiving app. Keep the calling app’s speakers set to your headphones or usual output. You can enable **Monitor voice** independently to hear the processed voice and pads. Changing devices while live briefly reconnects audio. If a device fails to open, Microphun attempts to restore the previous route.

Run `./scripts/build-driver.sh` and install `build/Microphun Audio Driver.pkg` for the native route. The driver supplies an input-only **Microphun Mic** for browsers and call apps and an output-only **Microphun Send** for the mixer. Both use a shared 48 kHz sample clock. It installs in `/Library/Audio/Plug-Ins/HAL/MicrophunAudio.driver`. If the devices do not appear after installation, restart Core Audio when you can interrupt audio or restart the Mac. [BlackHole 2ch](https://existential.audio/blackhole/) is supported as an alternate route. Local headphone monitoring works on its own. The app leaves system-wide sound preferences alone.

## Sound library

The **SpongeBob** bank has eight short community-sourced clips, including Boo-womp, Dolphin censor, My leg!, Squidward steps, Mr. Krabs walk, Moments later, SpongeBob laugh, and Bubble wipe. Each recording has a source in [SoundCredits.txt](Resources/SoundCredits.txt). The **Reactions** bank includes Anvil delivery, Awkward crickets, Printer tantrum, the original cartoon cues, and the [Apollo 13 recording](https://www.nasa.gov/historical-sounds/). Imported audio has its own bank.

BlackHole 2ch shares one device volume between its input and output. **Keep BlackHole at full volume** restores that gain if another app lowers it during a live send. The switch is in Routing and is also available as `microphun set hold-send-level off`. Microphun respects device mute. For Safari, set the BlackHole 2ch format to 48,000 Hz in Audio MIDI Setup. On this Mac, that configuration reproduced the test pad on both input channels with local monitoring enabled and disabled. In Atopile’s Audio & video preferences, choose BlackHole 2ch for the microphone. Sites that request the default microphone can receive the mix by selecting BlackHole 2ch as the Mac’s sound input and reopening the site’s mic.

## Houston radio and voice isolation

**Houston radio** processes your live speech with a narrow speech band, fast compression, soft saturation, gated carrier hiss, and a short sign-off chirp at the end of a phrase. Adjust **Amount** to blend in your natural voice. **Ghost choir** adds three detuned voices and reverb. **Tape deck** adds flutter, saturation, and slapback.

**Voice isolation** starts enabled. The app runs [RNNoise](https://github.com/xiph/rnnoise/tree/v0.1.1) locally on the microphone before applying effects. It reduces keyboard clicks and other background sounds. Some clicks can remain while you speak. The denoiser and its model ship in the app. The pinned source is version 0.1.1, commit `6cbfd53eb348a8d394e0757b4025c6ded34eb2b6`. Its license is in `Vendor/rnnoise/COPYING`.

## Command line

The bundled client controls the running app in the current macOS login session. It uses a local message port and prints JSON. With the app in its final location, link its client to a directory on your PATH. For a local build:

```sh
mkdir -p ~/.local/bin
ln -s "$PWD/build/Microphun.app/Contents/Helpers/microphun" ~/.local/bin/microphun
```

```sh
microphun open
microphun status
microphun devices
microphun route input "MacBook Pro Microphone"
microphun route send "BlackHole 2ch"
microphun preset houston
microphun set isolation on
microphun start
microphun pads
microphun play "My leg!"
microphun stop-pad
microphun stop
```

`microphun help` lists controls, including device selection, monitor testing, clip import, and live parameter changes. `microphun route monitor "DEVICE"` chooses the destination for local playback. `microphun set monitor-voice on` also sends your mic there. You can change routes during playback. `microphun route input off` selects soundboard only.

## Build

Requires macOS 13 or later and Apple’s Command Line Tools with a Swift 5.9 or newer compiler. Run the following commands from the checkout.

```sh
./scripts/build.sh
open build/Microphun.app
```

The script compiles for the current Mac, packages all resources, and ad-hoc signs the app. It accepts an optional build directory. No package manager or network connection is required to build.

## Check BlackHole in Safari

With Microphun live and sending to BlackHole 2ch, run `python3 scripts/check-safari.py`. Click **Test BlackHole 2ch** in the Safari tab. One Bonk plays through your current route. The page measures the waveform at Safari’s microphone and at the receiving end of a WebRTC connection inside the same tab. The audio stays on the Mac. Both the page and the terminal show the result. Close the tab or end the command with Control-C when finished.

## Verify the mixer

```sh
./scripts/build.sh
clang++ -std=c++17 -O2 Tests/MixerTests.cpp build/rnnoise/*.o -framework AudioToolbox -framework CoreAudio -framework CoreFoundation -o build/mixer-tests
build/mixer-tests
```

The mixer runs at 48 kHz. Microphun writes the mix to both BlackHole channels through a dedicated Core Audio output callback. The callback follows BlackHole’s sample rate. Microphone input and local monitoring use separate audio queues. A fractional reader compensates for drift between input, virtual output, and monitor clocks. The C++ voice path implements overlapping delay-tap pitch shifting, damped comb and all-pass reverb, ring modulation, vibrato, and sample-and-hold bit crushing. Pads enter after the voice effects. Monitor gain is independent of the call mix.
