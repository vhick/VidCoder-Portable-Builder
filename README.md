# VidCoder Portable — GitHub Actions Builder

A standalone **manual-only** GitHub Actions builder. It compiles the stable official VidCoder tagged source into a self-contained Windows x64 `App/` layout, applies narrowly scoped source fixes for portable data storage, and compiles a root `VidCoderPortable.exe` launcher carrying VidCoder's **original** icon.

This repository **does not contain** a prebuilt VidCoder executable. Running the GitHub Action creates the ready-to-extract portable artifact.

## Build — beginner instructions

1. Create a new **public** repository, such as `VidCoder-Portable-Builder`, in GitHub. It does **not** need to be a fork of VidCoder.
2. Extract this builder-kit ZIP onto your PC.
3. Using **GitHub Desktop** (simplest for `.github` workflows), commit and publish all extracted files into the repository. Keep the `.github/workflows/build-vidcoder-portable.yml` folder path exactly.
4. On GitHub, open your repository's **Actions** tab.
5. Select **Build VidCoder Portable (Manual)**, then click **Run workflow**. Leave the version as **latest** for the newest official stable release, or enter a known stable version such as `12.23`.
6. Once the run is successful, open that run and download **VidCoderPortable-[version]-x64** from **Artifacts**.
7. Extract the resulting artifact ZIP to a writable folder or external drive. Double-click **VidCoderPortable.exe** in its root. **Do not launch `App/VidCoder.exe` directly.**

If Actions shows no workflow, check that `.github/workflows/build-vidcoder-portable.yml` exists **exactly** at that location on your repository's default branch.

## Folder structure

```text
VidCoderPortable/
├── VidCoderPortable.exe        (original VidCoder icon; standalone native launcher)
├── App/
│   ├── VidCoder.exe            (self-contained upstream application, source patched)
│   ├── VidCoderWorker.exe      (self-contained worker)
│   ├── hb.dll                  (HandBrake engine)
│   ├── AppInfo/
│   │   ├── appicon.ico
│   │   └── appinfo.ini
│   └── ... dependencies
├── Data/
│   ├── Settings/              (created at launch: SQLite, presets, logs, backups)
│   ├── Temp/                  (created at launch; best-effort cleared on exit)
│   ├── Roaming/               (created at launch for process-local APPDATA)
│   ├── Local/                 (created at launch for process-local LOCALAPPDATA)
│   └── KEEP_DATA_README.txt
├── Other/
│   ├── License/
│   └── Source/                 (corresponding modified VidCoder source ZIP)
└── README-START-HERE.txt
```

## How to update your portable app

Run the workflow again. Unzip the new artifact into a new temporary folder, then copy **only `VidCoderPortable.exe`, `App/`, and `Other/`** into your existing VidCoderPortable folder. Replace existing binaries and files. **Do not replace or delete `Data/`.** Back up `Data/` before major upgrades because VidCoder can update its SQLite database schema.

## Why compile from source?

The stock official portable `.exe` may use an existing database in the host `%APPDATA%`, depending on whether a database exists beside the executable. This kit avoids that ambiguity by overriding the database location *in source*, before connecting to SQLite. The same override handles VidCoder's backup, logs, and cache AppFolder. The app is forced to classify this launch as portable (which disables the normal update and watcher behaviors).

The root launcher sets only **process-local** variables. It never changes the user's global Windows environment, registry, AppData, or ProgramData and never deliberately edits another VidCoder installation's data. Temporary files are redirected to its own `Data/Temp` and the launcher attempts to clear that folder after VidCoder closes.

This isolation covers known VidCoder app data paths. It **cannot guarantee zero OS-managed traces** (Windows itself and media drivers can create caches). Also, absolute paths in queued jobs may need adjusting after switching PCs.

## Important safety/testing notes

- This is a **builder kit**, not a Windows-tested portable binary. GitHub Actions compiles and checks the package structure; you still need to test on Windows 10/11 with a sample conversion, close/reopen settings, and audit traces.
- The build deliberately **fails** if upstream moves/changes the patched source locations; it will not silently ship a non-isolated version. Future major upstream changes may require changes to this kit.
- There is no scheduled Action, no automatic portable update, no `.paf.exe` builder, and no modification of your original upstream GitHub repository.
- Architecture: **x64**. Windows ARM64 is not included here.
- Use the package from a **writable** folder. Windows `Program Files` is usually not writable as a normal user.
- Do not launch the stock `App/VidCoder.exe` directly, because the source-level isolation requires the `VIDCODER_PORTABLE_DATA_DIR` environment variable supplied by the root launcher.
- A normal installed VidCoder instance must not be running at the same time; they share a named instance mutex.

## Official references

- Source repository: https://github.com/RandomEngy/VidCoder
- Official stable releases: https://github.com/RandomEngy/VidCoder/releases
- Portable-vs-ZIP behavior: https://vidcoder.net/Documentation/Installation.html
- License: VidCoder GPL-2.0; full modified source is shipped in every artifact (`Other/Source/`), along with the portable launcher source and build patch instructions.
