# Kai Live

Kai Live puts a full-duplex `gpt-live-1` conversation in the macOS menu bar. Click the robot, start talking, interrupt naturally, and watch both sides of the conversation arrive as live captions.

This repository is a working native Swift implementation of OpenAI's Live API. It covers the parts a voice demo usually skips: microphone conversion, ordered audio playback, session shutdown, API-key storage, transcript handling, and a menu bar interface that cannot leave a paid session running invisibly.

## What it does

- Runs as a menu bar app with no permanent Dock window
- Opens a visible setup window on first launch
- Starts a voice session when the conversation popover opens
- Captures and converts microphone audio to the Live session's PCM format
- Streams microphone and assistant audio at the same time
- Supports natural interruptions and overlapping speech
- Displays rolling captions for the user and Kai
- Shows input and output audio levels
- Supports mute, end conversation, Settings, and Quit
- Stores the OpenAI API key in macOS Keychain
- Keeps transcripts in memory only for the active session
- Closes the Live session when the popover is dismissed

## Requirements

- macOS 14 or newer, as configured in [`Package.swift`](Package.swift)
- An Xcode toolchain with Swift 6.2 support, as declared in [`Package.swift`](Package.swift)
- An OpenAI project with access to `gpt-live-1`
- A paid API tier, because OpenAI does not list the Free tier as supported

OpenAI currently documents GPT-Live voice sessions at **$0.05 per minute, billed per second**. The source for pricing and account limits is the [GPT-Live 1 model page](https://developers.openai.com/api/docs/models/gpt-live-1). Check it before relying on the number in this README.

## Build and run

Clone the repository:

```bash
git clone https://github.com/sabajamalian/kai-live.git
cd kai-live
```

Build the signed local app bundle:

```bash
./scripts/build-app.sh release
```

Run it:

```bash
open ".build/Kai Live.app"
```

The first launch opens **Kai Live Setup**. Enter your OpenAI API key, choose a voice, and edit Kai's conversation instructions if needed. After setup, click the robot icon in the menu bar to start a conversation.

macOS asks for microphone access when the first session begins.

## Install in Applications

```bash
./scripts/build-app.sh release
ditto ".build/Kai Live.app" "/Applications/Kai Live.app"
open "/Applications/Kai Live.app"
```

The build script creates an ad-hoc signed app for local use. It does not produce a notarized distribution build.

To uninstall:

```bash
rm -rf "/Applications/Kai Live.app"
```

The API key remains in Keychain unless you remove it from Kai Live Settings before uninstalling.

## Run the tests

```bash
swift test
```

The tests cover Live event encoding and decoding, session configuration, base64 audio events, and PCM level calculations.

## Architecture

```text
macOS status item and popover
            |
         AppModel
            |
    +-------+-------------------+
    |                           |
KeychainStore               LiveSession
                                |
                    wss://api.openai.com/v1/live/sessions
                                |
                         AudioPipeline
                         /           \
              microphone capture   playback queue
                    |                   |
              AVAudioConverter      AVAudioPlayerNode
                    |
               Live PCM audio
```

`AppModel` owns the UI state and active conversation. `LiveSession` owns the WebSocket lifecycle and the subset of Live events used by the app. `AudioPipeline` keeps microphone processing off the audio callback, converts device input to the session format, preserves chunk order, and queues assistant audio for playback.

The Live session starts with:

- model: `gpt-live-1`
- transport: WebSocket
- endpoint: `wss://api.openai.com/v1/live/sessions`
- audio: signed 16-bit little-endian PCM, mono, 24 kHz, following OpenAI's [WebSocket audio format](https://developers.openai.com/api/docs/guides/voice-websockets?api=live#choose-the-audio-format)
- delegation: client
- server-side session storage: disabled

Input and output transcripts are tracked independently. GPT-Live can listen and speak at the same time, so captions cannot assume strict alternating turns.

## Credentials, privacy, and cost control

Kai Live reads the API key from macOS Keychain at session startup. The key is not stored in `UserDefaults`, source files, logs, or transcripts.

The app does not persist raw audio or conversation transcripts. Captions exist only in memory and are cleared when the session ends.

Closing the popover ends the Live session. This behavior is deliberate because Live sessions are billed by duration. If the connection closes before the final `session.closed` event, the app reports that final usage could not be confirmed.

## Security and distribution boundary

This project is designed for personal use on a trusted Mac. The native client connects directly to OpenAI with the user's project API key.

OpenAI's [WebSocket guide](https://developers.openai.com/api/docs/guides/voice-websockets?api=live) describes standard project keys as server-side credentials. Do not ship a shared key inside this app or distribute a build preconfigured with one. A multi-user product should put credential handling and session creation behind a trusted service, then issue short-lived client credentials through a supported client transport.

## MCP server support

The current app does not execute MCP tools. The session already uses GPT-Live client delegation, which is the integration point for adding them.

A practical MCP implementation would:

1. Keep enough transcript and task state to understand a delegation request.
2. Receive `session.delegation.created` from GPT-Live.
3. Route the request to an enabled MCP server.
4. Require confirmation before writes, external messages, purchases, permission changes, or destructive actions.
5. Validate and reduce the MCP result to the facts Kai needs to say.
6. Return the result with `session.commentary.append` using the original delegation ID.

That work needs an MCP client, server configuration, process lifecycle management, JSON-RPC transport, tool schemas, permission policy, confirmation UI, timeouts, cancellation, and result redaction. The application must enforce those controls independently of the voice prompt.

## Known limitations

- No MCP tool execution or backend agent yet
- No saved conversation history
- No wake word or global keyboard shortcut
- No launch-at-login setting
- No Developer ID signing, notarization, update feed, or release download
- No echo cancellation beyond the audio behavior provided by the active macOS route
- Direct project-key authentication is suitable only for personal use

## Project structure

```text
Sources/KaiLive/
  AppModel.swift
  AudioPipeline.swift
  ConversationView.swift
  KaiLiveApp.swift
  KeychainStore.swift
  LiveProtocol.swift
  LiveSession.swift
  SettingsView.swift
  TranscriptRow.swift
Tests/KaiLiveTests/
Resources/
scripts/build-app.sh
Package.swift
```

## License

Kai Live is available under the [MIT License](LICENSE).
