# Contributing to Marquee

Thanks for helping out! This guide covers how changes get from an idea into `main`.

## Ground rules

- `main` is protected and always releasable. Nobody pushes to it directly, maintainers included. Every change lands through a pull request.
- One topic per pull request. Unrelated fixes go in separate PRs.
- Be kind. Assume good intent in reviews and issues.

## Reporting bugs and proposing features

- Search [existing issues](https://github.com/kuroega/marquee/issues) first.
- For a bug, include the tvOS version, the device or simulator model, the AList server version, steps to reproduce, and what you expected to happen.
- For anything bigger than a small fix, open an issue to discuss it before you write code. This matters most for UI or behavior changes, which should match [specs/spec.md](specs/spec.md).
- **Security issues:** don't open a public issue. Report them privately through [GitHub security advisories](https://github.com/kuroega/marquee/security/advisories/new).

## Development workflow

1. **Get the code.** Fork the repo (outside contributors) and clone it with its submodule:

   ```sh
   git clone --recurse-submodules https://github.com/<you>/marquee.git
   ```

   After pulling, run `git submodule update --init` so `alist/` matches the commit `main` expects.

2. **Branch from the latest `main`.** Use a `type/short-description` name:

   | Prefix | Use for |
   | --- | --- |
   | `feat/` | New user-facing features |
   | `fix/` | Bug fixes |
   | `perf/` | Performance work |
   | `refactor/` | Code changes with no behavior change |
   | `docs/` | Documentation only |
   | `chore/` | Build, tooling, dependencies, submodule bumps |

3. **Make the change.** Follow the style of the surrounding Swift code. Add or update tests in `AListTVTests` (and `AListTVUITests` for focus or navigation changes). Update `specs/` when you change specified behavior.

4. **Commit** using [Conventional Commits](https://www.conventionalcommits.org):

   ```text
   <type>(<scope>): <imperative summary>
   ```

   - `type` is one of `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `chore`.
   - `scope` is optional and names the area, e.g. `gallery`, `player`, `browser`, `topshelf`, `alist`.
   - Example: `fix(player): keep subtitle offset after seeking`.

   Explain *why* in the commit body when it isn't obvious. Keep commits focused, and squash fixup commits before you ask for review.

5. **Verify locally** before opening the PR:
   - The `AListTV` scheme builds for the tvOS Simulator with no new warnings.
   - Unit tests pass:

     ```sh
     xcodebuild test -project AListTV.xcodeproj -scheme AListTV \
       -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'
     ```

   - You tried the change in the tvOS Simulator, or on a device, against a real AList server. [RUNBOOK.md](RUNBOOK.md) shows how to run a local backend from `alist/`.

6. **Open a pull request** against `main`:
   - Describe what changed and why, and link the issue (`Closes #123`).
   - Attach screenshots or a short recording for any UI change.
   - Say how you tested it.
   - Keep the PR a draft until it's ready for review.

7. **Review and merge:**
   - At least one approving review is needed, and CI must be green (when configured).
   - Push follow-up commits to the PR branch rather than force-pushing over reviewed code. Rebase onto `main` only to resolve conflicts.
   - PRs are **squash-merged**, so the PR title becomes the commit on `main`. Make the title a valid Conventional Commit.
   - Delete the branch after merging.

## Server changes and the `alist` submodule

`alist/` is a submodule tracking the [`tvos-server`](https://github.com/kuroega/alist/tree/tvos-server) branch of kuroega/alist. Server code is never edited as part of a Marquee PR.

1. Open the server change as a pull request against `tvos-server` in [kuroega/alist](https://github.com/kuroega/alist). Changes that are generally useful should also go upstream to [AlistGo/alist](https://github.com/AlistGo/alist).
2. Once it's merged, open a separate Marquee PR that bumps the submodule pointer, titled `chore(alist): bump submodule to <short-sha>`.
3. A submodule bump must point at a commit that's already on the remote `tvos-server` branch, never at a local or unmerged commit.

## Secrets and private data

Never commit API keys, tokens, passwords, certificates, server addresses, or anything from your own network. That includes your TMDB key: keep it in the git-ignored `AListTV/Resources/TMDB.local.plist`. If you commit a secret by accident, rotate it right away. Removing it from git history isn't enough.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
