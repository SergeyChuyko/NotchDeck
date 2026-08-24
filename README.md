# NotchDeck

A hover panel that lives under the notch of a MacBook. Move the pointer to the notch and
the deck slides out; move away and it folds back. No window, no Dock icon — the app runs
as a menu-bar accessory.

Five sections: **Player**, **Search**, **Screenshots**, **Clipboard**, **Translator**,
plus a top strip with battery and a Wi-Fi toggle.

> Interface language is Russian. Source comments are Russian too.

## Sections

- **Player** — what is playing anywhere in the system (Music, Spotify, video in a browser):
  artwork, title, scrubbable position, transport controls. When the deck is collapsed, a small
  equalizer tinted by the artwork sits next to the notch.
- **Search** — a query field that opens Google in the default browser. While the field has
  focus the deck stays open, so moving the pointer away mid-typing does not close it.
- **Screenshots** — a grid of recent screen captures, newest first. Click copies (both the
  file and the image, since apps expect one or the other), drag pulls the file out, the
  buttons on a card open it or move it to the Trash. The folder is read from
  `com.apple.screencapture`, and files are recognized by Spotlight's `kMDItemIsScreenCapture`
  flag rather than by name, which is localized.
- **Clipboard** — history of copied text with pinning. Entries marked
  `org.nspasteboard.ConcealedType` (password managers) are never stored.
- **Translator** — Russian ↔ English on top of the system `Translation` framework. Runs
  locally, needs no key and no network; macOS downloads the language pack on first use.

## Requirements

- macOS 26.1 or later (the deployment target; the app uses the `Translation` framework and
  current SwiftUI APIs)
- Xcode 26 or later
- A Mac with a notch — on other displays the panel still works, but it is designed for the
  notch cutout and its geometry is derived from the screen's `safeAreaInsets`

The app is **not sandboxed** (`ENABLE_APP_SANDBOX = NO`), because the media bridge below
spawns a subprocess.

## Build

```sh
git clone https://github.com/SergeyChuyko/NotchDeck.git
cd NotchDeck
open NotchDeck.xcodeproj
```

Then set your own signing team in the target's *Signing & Capabilities* and run. There are
no third-party dependencies and nothing to install first.

On first use of the Screenshots section macOS asks for access to the folder where captures
are saved (usually Desktop). Without that grant the section shows an explanatory message
instead of the grid.

## How the media bridge works

Since macOS 15.4 the private `MediaRemote` framework answers only to processes signed by
Apple. A regular app gets an empty response — no client, PID 0, empty dictionary — even
while music is playing, and there is no public replacement (`MPNowPlayingInfoCenter` returns
only what your own app put there).

So `MediaAdapter/MediaRemoteAdapter.m` is built by an Xcode script phase into
`Resources/MediaRemoteAdapter.dylib` and is **not** linked into the app. Instead the app
spawns `/usr/bin/perl` — which is signed by Apple and still allowed — loads the dylib into
it, reads line-delimited JSON from its stdout and writes player commands to its stdin.

This is a deliberate workaround around a private framework. It may break on any macOS
update; when the bridge fails to start, the Player section shows the reason instead of a
track. Nothing else in the app depends on it.

## Layout

```
NotchDeck/Notch/     panel: window controller, shape, sections, per-section models and views
MediaAdapter/        Objective-C bridge to MediaRemote, loaded by perl (see above)
Docs/                NotchDeck.pdf and the program that generates it (Docs/source)
```

Panel geometry and colors live in `NotchConfig.swift`; the notch outline is in
`NotchShape.swift`.

## License

MIT — see [LICENSE](LICENSE).
