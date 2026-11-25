# Releasing HackrLFG

Releases are automatic: pushing a version tag runs `.github/workflows/release.yml`,
which uses the [BigWigs packager](https://github.com/BigWigsMods/packager) to build
the zip, upload it to CurseForge and attach it to a GitHub release.

## Every release

1. Test the change in game (`/reload`, no Lua errors).
2. Add a section at the top of `CHANGELOG.md`:
   ```
   ## 1.0.1

   - What changed, in player words.
   ```
3. Commit, tag and push (the tag *is* the version; don't edit `## Version` in the .toc):
   ```
   git add -A
   git commit -m "Release 1.0.1"
   git tag v1.0.1
   git push origin main --tags
   ```
4. Watch the run: `gh run watch` (or the repo's Actions tab).
5. Check the new file on CurseForge shows game version **1.60.1** (WoW Forever).

Version numbers: `1.0.x` for fixes, `1.x.0` for new features. Tags ending in
`-beta` or `-alpha` (e.g. `v1.1.0-beta1`) upload as Beta / Alpha files.

## One-time setup (already done once per addon)

- CurseForge project exists; its ID is in the .toc as `## X-Curse-Project-ID`.
- GitHub secret `CF_API_KEY` holds a CurseForge API token
  (set with `gh secret set CF_API_KEY`, which prompts for the value).
- `## Interface: 16001` in the .toc is what makes the upload WoW Forever.

## If the CurseForge upload lands on the wrong game version

The packager maps the .toc's Interface number to a CurseForge version. If Forever
files ever show up as another game version, pass it explicitly by changing the
last workflow step to:

```yaml
      - uses: BigWigsMods/packager@v2
        with:
          args: -g 1.60.1
```
