# Privacy

Twang is built to be boring about privacy.

| Question | Answer |
|---|---|
| Does it send data anywhere? | No. There is no telemetry, analytics, crash reporting or account. |
| When does it use the network? | Only when you press **Refresh** or **Install** in Settings > Library. HTTPS only; each download is verified against a SHA-256 published by the library. |
| What permissions does it need? | **Accessibility** (required): to notice your trigger and draw over other apps. **Screen Recording** (optional): only if you switch on the audio-reactive Equalizer, which listens to *system audio* (no video is used). |
| Does it record the screen or audio? | No. The Equalizer turns audio into 24 level numbers on the fly; nothing is stored. |
| Does it read my keyboard? | It listens for modifier keys (to detect a held ⌥ or Hyper) and Escape. It never records or stores keystrokes. |
| Does it read my clipboard, files or windows? | Not unless you switch on **real actions (beta)** in Settings > General. Then it can read the clipboard and keep a small in-memory history while it runs. |
| Is there a log? | Off by default. If you turn it on (Settings > General), `~/Library/Logs/Twang/gesture.log` records when and why gestures start and end (timings and reasons only). You can delete it any time. |
| Can a community animation pack spy on me? | No. Packs are JSON with a small formula language. They cannot run code, read files or use the network. |
| Where are settings stored? | macOS `UserDefaults` for the app (`co.tinyminotaur.twang`) and `~/Library/Application Support/Twang/Packs` for installed packs. |

To remove everything: quit Twang, delete the app, `~/Library/Application Support/Twang`, `~/Library/Logs/Twang`, and run
`defaults delete co.tinyminotaur.twang`.
