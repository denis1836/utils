# Asset Registry

## How to add a new asset pack?

1. Compress to zip: `Asset_Pack_Name_vX.Y.Z.zip` ([semantic versioning](/README.md#semantic-versioning-url))

2. Upload the ZIP to the Google Drive [Asset Folder](https://drive.google.com/drive/u/2/folders/1qv_ae8k4-zFgDKxuv7NrbR4PBdlzigwB)

3. Copy the url to the file

4. Create the JSON file via the template

5. Add the file hash to the `sha256` field by `sha256sum Asset_Pack_Name_vX.Y.Z.zip` bash command

6. `git add AssetRegistry/Asset_Pack_Name_vX.Y.Z.json`

7. `git commit -m "feat(assets): Add Car_Asset_Pack v1.4.12"` ([commit naming](/README.md#commit-naming-convention))

8. `git push`

## How to download the assets locally?

1. Check JSON file and download from the `drive_url` field

2. Download the ZIP from Google Drive

3. Extract to `install_path` folder

4. Open UE and wait for it to import
