# Native dictation integration

This is the first native integration of Handy-style dictation into Vorssaint.
It does not launch or automate the Handy application. Changes are intentionally
uncommitted while the integration is reviewed on the target Mac.

## Stages

1. **Source and architecture — implemented.** Inspected Handy at
   `7bfb2e2c934b798bcf6e3627653aed2439996f89`. Reuse its pinned model catalog
   and its inference dependency, transcribe.cpp 0.4.0 at
   `f1dcd15858c4bbba87ca97862b4e448b2cf15b8f`. Keep the Tauri application
   out of the native app. Dependency and model-license links ship with the app.
2. **Local dictation — implemented; hardware acceptance pending.** Native
   microphone capture, Fn or a configurable shortcut, hold/toggle/hybrid modes,
   cancellation, elapsed time, audio imports, language hints, supported-model
   translation, vocabulary hints, deterministic corrections and text delivery.
3. **Vorssaint surfaces — implemented; interaction acceptance pending.** A
   dedicated Settings page, Features-hub availability, an opaque recording island
   that expands downward and sideways, processing/result/error states, and a
   searchable island history widget.
4. **Validation — automated coverage implemented.** Build, app selftest, full
   repository regression suite, native view fixtures and real-model worker smoke
   test. Physical Fn, microphone permissions, Bluetooth/headset transitions,
   target-app insertion and multi-display animation still need hands-on testing.
5. **Remaining Handy parity — future migration.** Interim streaming text,
   Silero VAD, speech-based language detection, advanced long-form chunking,
   multiple named cleanup providers/prompts and native Apple Intelligence,
   per-channel/clamshell microphone overrides, always-on recording buffers,
   muting playback during recording, automatic submission, direct typing and
   external-script delivery, exact Handy text-normalization/fuzzy-correction
   behavior, and migration of existing Handy settings/history. Advanced settings
   labels and diagnostic messages currently use English; the core dictation
   labels and microphone permission descriptions cover every supported locale.

## Architecture and lifecycle

- `DictationService` owns one recording or transcription job at a time. Each
  operation has a generation so late replies cannot publish after cancellation.
  Lock, sleep, session deactivation and input-device reconfiguration end capture.
- `DictationRecorder` captures the selected CoreAudio input into an owner-only
  CAF file with AVAudioEngine. Waveform samples come from actual input energy.
  Microphone access starts only after an explicit recording action.
- `DictationEngine` converts audio to 16 kHz mono float32 on a serial queue,
  then exchanges JSON lines with `VorssaintDictationWorker`. No shell commands
  run during transcription. The native model stays in a separate process,
  remains warm for a configurable interval and can be terminated on cancellation
  or a processing timeout. A GPU crash does not crash Vorssaint. CPU mode is
  available as an explicit fallback.
- `DictationModelStore` ships a static catalog and checks downloaded model size
  and SHA-256 before installing. Downloads can be cancelled. Models can also be
  imported explicitly; imported weights do not receive a catalog checksum.
- `NotchService` observes phase changes, leaving the existing native window
  host responsible for shape animation. The dictation surface remains opaque
  even when other island surfaces use glass. It does not take keyboard focus
  from the app receiving speech. Dictation temporarily takes presentation
  precedence over the normal module page and compact activities.
- `DictationHistoryStore` serializes private history writes. It keeps original
  and edited text, dates, model/language, recording duration, processing time
  and favorites. Entries support copy, search, editing, deletion and JSON export.
  Retained audio additionally supports playback and transcription again.

## Privacy and delivery

The feature is opt-in under **Features → Dictation** and has its own enable
switch. No model is downloaded automatically. The microphone is closed at rest.
Recognition runs locally; models require a network download once. Recordings
are discarded by default. Optional retained recordings expire lazily when the
history is opened, preferences are synchronized or a transcript is added.
Transcripts and audio are stored in private Application Support files, outside
settings backups. Machine-specific model/input selections and private vocabulary
and replacement dictionaries are also excluded from backups.

**Copy** is the default output. Automatic paste requires Accessibility, no Secure
Event Input and the original target app to remain active. Focus changes fall
back to copying. Paste-and-restore uses the existing serialized transient
pasteboard service, with an additional focus predicate immediately before
posting the paste shortcut. That service restores the prior clipboard only if
nothing else has replaced its content. A success label reports that the shortcut
was posted; there is no receipt from the destination app proving insertion.

Optional text cleanup is off by default. Enabling it sends transcript text to
the configured OpenAI-compatible chat-completions URL. HTTPS is required except
on loopback for a local server. Audio is never sent by this path. Credentials
are kept in Keychain and excluded from preferences/backups. A cleanup failure
preserves the original transcript and does not silently paste a partial result.

## Building and checking

`build.sh` now builds and signs a statically linked speech worker and includes
the catalog and notices in the bundle. CMake is required in addition to the
existing Xcode tools. The first build downloads the pinned engine source into
the ignored `.build` directory. Subsequent builds reuse its incremental output.
The app's Swift package remains an editor/indexing aid; `build.sh` assembles
the runnable app with its worker and resources.

```sh
./build.sh --dev
./build/VorssaintDeveloper --selftest
./build.sh --test
./build/VorssaintDeveloper --dictation-presentation-test
python3 Tests/dictation-engine-smoke.py /path/to/model.gguf \
  .build/transcribe-cpp-source/samples/jfk.wav
```

The presentation probe uses inert recording-state fixtures; it does not record
the microphone, post input events or copy text. It exports native view images
under `build/dictation-previews`. These fixtures verify layout, not the full
window-server animation or real input handling.

Validation on this checkout (Mac16,12, macOS 27.2; app built against the
macOS 26 SDK): optimized and Developer bundles built without Swift warnings,
both app selftests passed, all 117,827 regression checks passed, and the native
island host probe passed 2,603 samples with zero top/content alignment error.
The worker transcribed the public JFK fixture twice with Metal using the
checksum-verified Moonshine Tiny Q8_0 model, including warm-model reuse.
These results do not establish real microphone, shortcut or target-app behavior.

For the first hands-on session: enable the feature and island, download a model,
grant Microphone and Accessibility, and disable macOS's existing Fn action in
Keyboard settings if Fn is used. Check hold and quick-tap recording, Escape,
clipboard delivery, paste into the original app, focus-change fallback, history
copy/edit/favorite, and stop/cleanup on lock. Handy should be closed or assigned
a different shortcut while testing Fn to avoid two apps handling the same key.

Repository ownership, remotes and publishing are deliberately deferred. This
work does not change remotes, make commits, push branches or create a PR.
