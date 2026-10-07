# FloatNotes 0.4 — Listen and Capture

A small, resizable Mac window with two main actions:

- **Listen → Stop:** transcribe computer audio and/or microphone, then answer in text.
- **Capture:** take one screenshot and analyse it using your saved context; answer in text.

Context and Settings remain available. Nothing listens or captures automatically.

## Install this update

Requires macOS 15+, Swift 6 and the macOS 15+ SDK (Xcode 16+ or matching Command
Line Tools). Quit any older FloatNotes app using Command-Q. Extract the ZIP,
then run:

```bash
cd ~/Downloads/FloatNotesMac
bash scripts/install.sh
```

Use your actual extracted folder path if it differs. This builds, signs,
installs and opens **`~/Applications/FloatNotes.app`**. The title is
**FloatNotes 0.4**. Use this installed copy, not an older Downloads/Dock copy.

To reopen later, do **not** rebuild:

```bash
open ~/Applications/FloatNotes.app
```

If tools are missing, install them first with `xcode-select --install`.
No Python, Homebrew, virtual audio driver or third-party Swift package is needed.
The installer refuses to replace a running FloatNotes process.

## First use

1. Open Settings, enter your OpenAI API key and Save. If the key is already in
   Keychain but blocked, click **Unlock saved key** to authorize access explicitly.
2. Configure computer audio and, optionally, your microphone. Refresh the mic
   list if necessary. Choose speakers/headphones in macOS Sound or the meeting app.
3. Click Context to save your AI role, background and preferred response style.
4. Click Listen or Capture. Grant the relevant macOS permission when asked.

Display/audio preferences and context remain in
`~/Library/Application Support/FloatNotes/settings.json`. The API key remains
in Keychain. Settings Save returns to the overlay; opacity persists after restart.

## Listen

Click Listen, then speak or play audio. Text appears in roughly four-second
chunks plus API latency. Click Stop: recording ends, the last partial chunk is
transcribed, and the AI generates a text answer. No spoken response is created.
The next Listen begins a new transcript, while retaining your saved Context.

## Capture

Click Capture while idle. It captures the **entire display containing the pointer
when clicked** (normally the display containing FloatNotes). Move the overlay to
another display first if that is the one you want. Capture does not record audio
or start a continuous screenshot loop.

The app asks ScreenCaptureKit to exclude FloatNotes' own windows from its own
screenshot. The screenshot is JPEG-encoded in memory, limited to 2048 pixels on
the longest edge, and sent to OpenAI along with saved Context. The analysis
appears in Response. Existing transcript text remains visible but is not sent
as part of this independent screen-analysis request. Screenshots are not saved
to disk. Zoom very small text before capturing if the model cannot read it.

Context controls both actions. For example:

> Act as a senior data engineering coach. Answer in simple English. When you
> see code or an error on screen, explain the cause and give a minimal fix.
> Keep responses short and practical.

A context snapshot is used for each request. Responses remain text-only.

## Permission repair and repeated prompts

There are three distinct permissions/errors. The new version labels them separately:

| Message | What it means / what to do |
| --- | --- |
| macOS microphone access denied | Enable the installed FloatNotes under Privacy & Security → Microphone. Quit fully and reopen. |
| macOS Screen & System Audio Recording denied | Enable the installed copy under Privacy & Security → Screen & System Audio Recording. Quit fully and reopen. |
| Saved API key locked / Keychain error | Click Unlock saved key in Settings, or paste your key again. This is not screen-recording permission. |
| OpenAI API 401/403/429 | Check API key, project/model access or API quota. Changing macOS permissions will not fix an API rejection. |

### If macOS says allowed but the app says denied

1. Quit every FloatNotes copy. Install once using the command above.
2. In System Settings → Privacy & Security, check the **installed copy** at
   `~/Applications/FloatNotes.app`. Use the plus button if that pane provides one.
3. Toggle its Screen & System Audio Recording permission off and back on. Do
   the same for Microphone if using it. Follow any Quit & Reopen instruction.
4. Launch `~/Applications/FloatNotes.app` again, then click Listen or Capture.
5. If a stale entry still blocks it, quit the app and reset **only FloatNotes'**
   recording/microphone approvals, then reopen and grant them again:

   ```bash
   tccutil reset ScreenCapture local.floatnotes.mac
   tccutil reset Microphone local.floatnotes.mac
   open ~/Applications/FloatNotes.app
   ```

These optional commands intentionally remove previous approval for this app.
They do not grant access. They are not run by the app or install script. Do not
run them routinely, because resetting permissions makes macOS ask again.

### Why rebuilds can ask again

Previous builds always used `codesign --sign -` (ad-hoc signing). That identity
can change when the binary changes, so macOS can treat an update as a new app.
A stable install path helps avoid opening the wrong copy but does not by itself
fix changing signing identity.

The new build script automatically uses an Apple Development or Developer ID
Application certificate when exactly one suitable identity is available. With
multiple certificates, choose explicitly; list them with:

```bash
security find-identity -v -p codesigning
```

Then build/install using the exact identity name or hash from that output:

```bash
SIGNING_IDENTITY="YOUR_CODE_SIGNING_IDENTITY" bash scripts/install.sh
```

Use the same valid certificate for subsequent builds. If no certificate is
available, the build still works with ad-hoc signing, but **permissions may need
renewing after updates**. We cannot bypass macOS approval or guarantee that the
OS will never re-prompt. Reopening the same installed binary does not require
rebuilding it. Apple confirms the ad-hoc signing issue in its developer forum:
https://developer.apple.com/forums/thread/819406

The app no longer asks for microphone permission or enumerates microphones on
launch. It reuses authorized microphone status and requests only when the state
is undetermined and Listen actually needs the microphone. It does not make
explicit repeated screen-permission requests at startup or reject capture solely
based on a cached preflight flag. The actual ScreenCaptureKit operation decides
access when invoked. Settings → Refresh audio apps can also ask for screen access.
Keychain reads at launch are noninteractive; authorization is explicit via Unlock.

## Validation status

Source revision only: this environment is Linux without Swift, macOS SDKs or
Mac hardware. Shell syntax, app metadata and request wiring were checked.
**Compilation, native UI, screen capture, hardware and permission repair are
not verified here.** The exact denial on your Mac has not been reproduced.

Run the included unit tests on a Mac:

```bash
swift test
```

Tests cover audio decoding, WAV output, preference persistence, prompt construction,
screenshot request encoding and response parsing. Then check:

1. Reopen the installed binary twice without rebuilding: no app-initiated mic or
   Keychain prompt at startup. If the OS still asks, identify the exact prompt.
2. Listen/Stop with computer audio, microphone, then both; confirm final text.
3. Capture a visible question: one screenshot, no microphone prompt, text answer.
4. Test Capture on a second monitor by moving FloatNotes there first.
5. Save context, change opacity, quit and reopen: both persist.
6. Denied capture access versus an invalid API key: each should show its own error.

If access still fails, share the **full displayed error text** and whether the
alert mentions Keychain, Microphone, or Screen Recording. For a crash, use the
newest FloatNotes entry in Console → Crash Reports (Exception Type, Termination
Reason and Crashed Thread). Never share your API key.

## Modules

| File | Responsibility |
| --- | --- |
| FloatNotesApp.swift / OverlayView.swift | Floating window and Listen/Capture UI |
| SettingsView.swift / ContextView.swift | Configuration and saved context editor |
| EditorWindowController.swift | Independent retained editor windows |
| AppModel.swift | Listen/Stop/Capture state and AI responses |
| PermissionService.swift | On-demand capture access and specific errors |
| ScreenshotService.swift | One display screenshot; own-app exclusion; JPEG encoding |
| CaptureService.swift / AudioChunker.swift / PCMDecoder.swift | Audio capture and safe chunk encoding |
| WAVEncoder.swift | In-memory WAV files |
| OpenAIClient.swift | Transcription, text requests and image analysis requests |
| ResponsePrompt.swift | Saved context for audio or screenshot analysis |
| PreferencesStore.swift / KeychainStore.swift | Preferences and API-key storage |
| scripts/build.sh / scripts/install.sh | Build/sign and install to a stable location |

## Practical limits

- All audio/images submitted by these actions go to OpenAI; saved context goes
  with answer requests. API quota is required. Defaults remain
  `gpt-4o-mini-transcribe` and `gpt-4.1-mini`.
- Chunked transcription can split sentences. Labels distinguish computer audio
  from mic, not individual speakers. Headphones reduce mic echo duplication.
- A slow transcription queue can cause a reported stop; very long sessions may
  exceed the answer model's context limit. Intended for short personal sessions.
- The app can exclude itself from **its own** screenshot; it cannot guarantee
  invisibility in someone else's screen-share capture. Share a specific app
  window and verify the remote view if needed.
- Use recording/capture and AI assistance where permitted.

To uninstall, clear the API key in Settings and Save, quit, delete
`~/Applications/FloatNotes.app` and your project folder. Remove
`~/Library/Application Support/FloatNotes` to delete saved preferences/context.
