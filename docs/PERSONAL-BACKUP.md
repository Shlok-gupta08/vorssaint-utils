# Personal Vorssaint backup

Private repository: https://github.com/Shlok-gupta08/vorssaint-dictation-backup

This preserves the complete personal `dev/combined-features` checkout, including
local dictation and the existing personal camera/music/lock-screen work. The
upstream dictation PR is maintained separately on `feat/local-dictation-island`
from the creator's current `main`; its scope excludes those unrelated changes.

## Recover the source

```sh
git clone git@github.com:Shlok-gupta08/vorssaint-dictation-backup.git
cd vorssaint-dictation-backup
git checkout dev/combined-features
./build.sh --dev --install
```

The build requires Apple Silicon, macOS 14+, Apple's command-line tools and CMake.
It fetches the pinned native engine source. Models are downloaded/imported through
Dictation settings after launch. Permissions and local model files are separate
from Git and must be configured on the recovering Mac.

## Recover the installer

The private repository's Releases page contains the personal DMG and SHA256SUMS.
Download both and verify with `shasum -a 256 -c SHA256SUMS`. This is a locally signed
personal build, not an official upstream release or a notarized distribution.
The installer contains the standard Vorssaint app; the separately installed
Developer app uses its own bundle ID and preferences. Enable Dictation in Features
and download/select a model when using a fresh installation.

The October 30 snapshot (`personal-backup-2026-10-30`) includes the current
personal tree: Antigravity activity from T3 Code and the local hub, the AI Agents
Controls shortcut, the updated agent layout and icons, media paging and timelines,
expanded island sizing, consistent expanded-state padding, the charging indicator
clearance, automatic Stay Awake for active AI agents, sleep prevention during
dictation, and the volume/brightness and lock-screen refinements.
Its release keeps the DMG, this recovery guide and `SHA256SUMS` together.
The older October 27 installer remains available in its original release, with
source preserved by `bde80cb6`.
Transcripts, recordings, API keys, signing keys, downloaded models and application
preferences are intentionally excluded. Models can be downloaded again using the
pinned catalog. Runtime credentials remain in Keychain.

## Remotes in the original working folder

- `backup`: this private repository, with `dev/combined-features` as the default
  branch and the current branch's upstream/push destination.
- `origin`: the public fork `Shlok-gupta08/vorssaint-utils`, used for PR branches.
- `upstream`: the creator's repository `vorssaint/vorssaint-utils`.

On the original personal branch, normal `git push` saves future commits privately.
The public dictation branch has an explicit public push destination so its PR
can be updated separately. A fresh clone of this private repository naturally
uses it as `origin`. Actions are disabled here because this repository is a
personal backup rather than a copy of the creator's release pipeline.
