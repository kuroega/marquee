## Verify Rule

- For any tvos app development, bug fix, or modification on the existing features, etc., please make sure you always verify the code changes in the macOS tvos 27.x simulator. (this rule only applies to the agent working in macOS)
- If the tvOS App build requires VLCKit, please reuse `~/Developer/SDK/VLCKit-4` first before download a fresh new one. Always double confirm with human if you need to do a fresh download of the VLCKit from internet.

## VLCKit Binary

The project pins VLCKit `4.0.0-a22`, which is an SPM binary target: an 865 MB zip from download.videolan.org. That server is often very slow from here (about 14 KB/s, which means hours), and xcodebuild downloads it again whenever a DerivedData folder's `SourcePackages/artifacts` is empty. `-disableAutomaticPackageResolution` and `-skipPackageUpdates` don't stop that download.

Local copies on the maintainer's Mac:

| Path | What |
| --- | --- |
| `~/Developer/SDK/VLCKit-4.0-20260720-1538.zip` | The original zip as published. SHA-256 `d9de86d0c755cbcf46c49513ff57fffcd98258f0c7dd29f3e2d23bff3860da2a`, the same checksum as VLCKit's `Package.swift`. |
| `~/Developer/SDK/VLCKit-4/VLCKit.xcframework` | The xcframework unpacked from that zip, with tvOS device and simulator slices. |

- Check that these files exist before building. If they're missing, ask the human to download the zip in a browser rather than letting xcodebuild fetch it.
- To build without the download, override the package locally:
  1. Outside the repo, make a folder named `VLCKit`.
  2. Clone the xcframework into it with `cp -cR` and run `xattr -cr` on the copy.
  3. Add a `Package.swift` that declares `.library(name: "VLCKit", targets: ["VLCKit"])` and `.binaryTarget(name: "VLCKit", path: "VLCKit.xcframework")`.
  4. Create an `.xcworkspace` that references both that folder and `AListTV.xcodeproj` by absolute path.
  5. Build with `xcodebuild -workspace <that>.xcworkspace -scheme AListTV …`.
- If VLCKit is bumped, the zip name and checksum change. Update this table once the new zip is downloaded.

## Contribution Workflow

- Follow [CONTRIBUTING.md](CONTRIBUTING.md). Never commit or push to `main` directly. Branch from the latest `main` using one of the prefixes `feat/`, `fix/`, `perf/`, `refactor/`, `docs/`, `chore/`, and land changes through a pull request.
- Commit messages use Conventional Commits: `<type>(<scope>): <imperative summary>`, where the scope names an area (`gallery`, `player`, `browser`, `topshelf`, `alist`, ...). Don't use the old `tvos` scope now that the whole repo is the tvOS app.
- Never commit secrets, server addresses or anything from the local network. `AListTV/Resources/TMDB.local.plist` and `scripts/install-*.fish` stay git-ignored.

## Submodule Pointer Update

`alist/` is the AList server and tracks the `tvos-server` branch of `https://github.com/kuroega/alist.git`. It's only used as the local test backend, and the app talks to it over the HTTP API.

- After switching branches or pulling, run `git submodule update --init` so `alist/` is checked out at the recorded commit. If `git status` shows `modified: alist (new commits)` and you didn't change the server, the checkout is stale. It doesn't need a bump.
- Make server changes inside `alist/`, never as part of an app change:
  1. `cd alist && git switch tvos-server && git pull --ff-only`
  2. Branch, commit, and open the PR against `tvos-server` in kuroega/alist. For Go code, run `go test` on the packages you touched and build with `go build -tags=jsoniter .`.
  3. Once it's merged, update the pointer from the repo root, on its own branch and in its own PR:

     ```sh
     git submodule update --remote alist
     git -C alist log --oneline -1          # confirm the expected commit
     git add alist
     git commit -m "chore(alist): bump submodule to $(git -C alist rev-parse --short HEAD)"
     ```

- The recorded commit must already exist on `origin/tvos-server`. Before committing the bump, check with `git -C alist branch -r --contains HEAD`. Never record a local-only or unmerged commit.
- Keep submodule bumps in their own commit and PR, separate from app changes. The only exception is an app change that depends on the new server commit; in that case, say so in the PR description.
- To pick up upstream AList fixes, merge `main` from `AlistGo/alist` into `tvos-server` in the fork (ask the human first), then bump the pointer as above.
- Never edit `.gitmodules` to point at another URL or branch without the human's confirmation.
