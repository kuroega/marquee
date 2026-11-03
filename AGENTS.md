## Verify Rule

- For any tvos app development, bug fix, or modification on the existing features, etc., please make sure you always verify the code changes in the macOS tvos 27.x simulator. (this rule only applies to the agent working in macOS)
- If the tvOS App build requires VLCKit, please reuse `~/Developer/SDK/VLCKit-4` first before download a fresh new one. Always double confirm with human if you need to do a fresh download of the VLCKit from internet.

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
