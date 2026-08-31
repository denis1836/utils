# ue5-asset-downloader

Me and my friends needed a way to share UE5 asset packs (meshes, maps, actors etc.) without shoving giant binaries into the repo, so git just tracks metadata the actual zips are on Google Drive.

## How it works

- assets live on Google Drive as zips
- each pack gets a small JSON file in `AssetRegistry/` describing it (version, hash, where to unpack it, etc.)
- `download-assets` reads those JSONs, lets you pick a pack, downloads it, checks the sha256, unzips it into your project
- a pre-commit hook stops you if your JSON is broken before you push garbage

## Requirements

- bash
- python3
- curl or wget
- unzip
- file

## Setup

```bash
git clone <todo link>
cd ue5_asset_downloader
```
Also you can install a pre-commit so it'll check if you have all the assets before you commit.

```bash
./installers/install-pre-commit.sh
```

## Downloading a pack

```bash
./download-assets
```

Pick a number, `a` for all of them, or `q` to bail. It'll fetch the zip from Drive, verify the checksum if there is one, and drop it into the path defined in the JSON. Open UE and let it import.

## Adding a new pack

1. Zip it up: `Asset_Pack_Name_vX.Y.Z.zip` *([semver](https://semver.org/))*
2. Upload to your GoogleDrive, set sharing to "anyone with the link"
3. Copy the file's share link
4. Copy `AssetRegistry/Example_Asset_Pack_v1.0.0.json`, fill it in
5. Get the hash: `sha256sum Asset_Pack_Name_vX.Y.Z.zip`, drop it in `sha256` field
6. `git add AssetRegistry/Asset_Pack_Name_vX.Y.Z.json`
7. `git commit -m "feat(assets): add Asset_Pack_Name_vX.Y.Z"`
8. `git push`

The pre-commit hook will check your JSON on commit, so you'll know if you screwed something up.

## JSON fields

```json
{
  "name": "Example_Asset_Pack",
  "version": "1.0.1",
  "date": "2026-06-03",
  "author": "John Smith",
  "description": "Some Basic shapes",
  "file": "Example_Asset_Pack_v1.0.1.zip",
  "download_url": "https://<url>",
  "sha256": "<hash>",
  "ue_version": "5.7.4",
  "install_path": "Content/<path>",
  "contents": [
    "Cube1", 
    "Triangle1",
    "Sphere1",
    "Cylinder1"
    ],
  "depends_on": [],
  "changelog": [
    "v1.0.0 - Add basic shapes",
    "v1.0.1 - Fix Triangle1 mesh"
  ]
}
```

Most of it is self explanatory. `file` has to match the JSON's filename (minus extension), `install_path` is relative to your project root, `download_url` needs to be a Drive link (either the `/file/d/<id>/view` or `?id=<id>` flavor), `depends_on` isn't enforced anywhere yet(but you still have to download other dependencies assets).

## Config

`download-assets.conf`:

```bash
REGISTRY_DIR="./AssetRegistry"
DOWNLOAD_DIR="./.asset-downloads"
```

Change these if you move stuff around. `DOWNLOAD_DIR` is just a temporary download folder, gets cleaned up after install.

## Pre-commit hook

Only runs on staged files inside `AssetRegistry/*.json`. Blocks the commit if:

- JSON doesn't parse
- a required field is missing
- `sha256` or `download_url` is still the `<placeholder>` from the template

Warns (but lets you through) if `version` isn't semver, `date` isn't `YYYY-MM-DD`, `file` doesn't end in `.zip`, or the filename doesn't match the `file` field.

## Commit style

```
feat(assets): add Car_Asset_Pack v1.4.12
```

`feat` / `fix` / `chore` / `docs`, whatever fits.

## Limitations

- only Google Drive links work
- the file has to actually be public or you'll download an HTML error page instead of a zip
- `depends_on` is decorative for now
- no other file hosts supported yet

## License

[MIT](https://github.com/denis1836/utils/blob/main/LICENSE.md)