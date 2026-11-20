# git-remote-tino

Source: `modules/pkgs/_tino/git-remote-tino.py`.

## Usage

TINO speaks no git wire protocol, so this remote helper bridges git to a bucket's REST API. Buckets can then be cloned, fetched and pushed from machines with no NetBird path to the TINO host.

```sh
git clone tino::abc-meetings      # or tino://host/abc-meetings
git fetch                         # GET /git/log, /git/changed/{sha}, /git/show/{sha}/content/{path}
git push                          # per commit: PUT/DELETE files, then POST /git/commit
```

- **API key**, first found: `TINO_API_KEY`, `$XDG_CONFIG_HOME/tino/api-key`, or the URL's userinfo (`tino://tino_<token>@host/bucket`). git stores remote URLs in `.git/config`, so prefer the file. Pushing needs *committer* on the bucket; reading needs *editor*.
- **Base URL**, first found: the `tino://` URL's host, `TINO_URL`, `git config tino.url`, else `https://tino.lvdar.nl` (the public netbird-proxy name).
- Pushed commits are authored as the API key's identity: TINO stamps the authenticated user. For human authorship, commit through TINO's UI.

## Refs

- A bucket is one branch, `master`; any `refs/heads/*` push destination lands there.
- Fetch builds a fast-import stream, not a pack. The stream is deterministic (author = committer, both dated from the server's `committed_date`), so re-importing unchanged history reproduces the same SHAs.
- Local SHAs never equal the server's: the log endpoint exposes only message, author and commit date. The helper therefore never compares object IDs across the bridge. The import also writes the materialized tip to the private ref `refs/tino/<slug>/master`, and push replays `refs/tino/<slug>/master..refs/heads/master`, fast-forward only, since TINO can neither merge nor force.
- The refspec is `*:*`, so clone and fetch write plain `refs/heads/master`.

## List reporting

`list` reports the marker ref's sha while the server tip still matches the tip cached at the last import or push, and `?` otherwise, which makes git import or push.

It never uses the `unchanged` attribute. With the identity refspec, git reads `unchanged` as "the remote matches the local branch", so local commits produce "Everything up-to-date" without a push.
