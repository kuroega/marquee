# Marquee

A native Apple TV client for [AList](https://github.com/AlistGo/alist) servers.

Marquee turns the files on your AList server into a library you can browse from the couch.

- **Gallery.** Shows and movies appear as poster shelves using TMDB metadata, with a *Watching* row that tracks started series until you've seen every episode.
- **Files.** *Recents* and a full *Browse* view of your storages.
- **Player.** Built on VLCKit, so MKV, HEVC, multiple audio tracks and styled (libass) subtitles play natively.
- **Top Shelf.** Your *Watching* shows on the tvOS home screen.

> Marquee is an unofficial, community client. It is not affiliated with the AList project.

## Requirements

- Xcode with the tvOS 17+ SDK
- An AList v3 server. Release builds accept only HTTPS. Debug builds also allow HTTP on private/local addresses for testing.
- A TMDB API key for Gallery metadata (optional, but Gallery is empty without it)

## Getting started

```sh
git clone --recurse-submodules https://github.com/kuroega/marquee.git
cd marquee
cp Config/TMDB.local.plist.example AListTV/Resources/TMDB.local.plist   # add your TMDB key
open AListTV.xcodeproj
```

Pick your team under *Signing & Capabilities*, then run the `AListTV` scheme on an Apple TV or the tvOS Simulator.

## Repository layout

| Path | Contents |
| --- | --- |
| `AListTV/` | App sources (SwiftUI) |
| `AListTVTopShelf/` | Top Shelf extension |
| `AListTVTests/`, `AListTVUITests/` | Unit and UI tests |
| `Config/` | Info.plists, entitlements, TMDB config template |
| `specs/` | Behavior spec, API contract and test traceability |
| `alist/` | AList server ([kuroega/alist@tvos-server](https://github.com/kuroega/alist/tree/tvos-server)), as a git submodule for local backend testing |

The submodule is only needed to run a local test backend. The app itself talks to any AList server through the standard HTTP API. To build and run that backend and validate on a device, see [RUNBOOK.md](RUNBOOK.md) (in Chinese).

Update the submodule to the latest server branch with:

```sh
git submodule update --remote alist
```

## Acknowledgements

- [AList](https://github.com/AlistGo/alist), the file server this app is a client for
- [VLCKit](https://code.videolan.org/videolan/VLCKit), the media playback engine (LGPL-2.1)
- [TMDB](https://www.themoviedb.org), which supplies the metadata and artwork. This product uses the TMDB API but is not endorsed or certified by TMDB.

## License

Marquee is released under the [MIT License](LICENSE). The `alist` submodule is a separate work under its own [AGPL-3.0 license](https://github.com/AlistGo/alist/blob/main/LICENSE).
