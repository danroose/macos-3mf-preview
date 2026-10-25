# macos-3mf-preview

Enables 3D previews in macOS for `.3mf` files.

Select a `.3mf` file in Finder and press **Space** to see an interactive 3D view of the model in its real filament colors. Drag or swipe to rotate it and pinch to zoom. You can check a model without opening your slicer.

- **3D Quick Look preview:** rotate and zoom with the mouse or trackpad. The bottom corner shows the model's size in mm and its triangle count.
- **Live Finder preview pane:** the model slowly spins on its own in the column-view or gallery-view side pane. Swipe with two fingers on the trackpad to rotate it yourself.
- **Real colors:** reads filament colors and painted regions from Bambu Studio, OrcaSlicer and PrusaSlicer projects, plus standard 3MF material colors.
- **Finder thumbnails:** icons show the plate image your slicer saved in the file, with no "3MF" badge on top. Files without a saved image get a 3D render instead.
- **Fast:** a 100 MB, 1.3-million-triangle model opens in under half a second on Apple Silicon.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later, to build from source (the free version from the App Store is fine)

## Install

There is no prebuilt download yet, so you build it yourself. It takes about a minute.

```sh
git clone https://github.com/danroose/macos-3mf-preview.git
cd macos-3mf-preview
make install
```

`make install` does the following:

1. Builds `3MF Preview.app`.
2. Copies it to `/Applications`.
3. Registers it with macOS.
4. Opens it once so the Quick Look extensions load.
5. Resets the Quick Look cache.

A small window confirms the install, and you can close it. The app doesn't need to stay running.

### Check that it's enabled

The extensions are normally enabled automatically. If pressing Space still shows a generic icon:

1. Open **System Settings → General → Login Items & Extensions**.
2. Scroll to **Extensions** and click the ⓘ next to **Quick Look**.
3. Turn on **3MF Preview** and **3MF Thumbnail**.

### Signing

By default the build uses an ad-hoc signature ("Sign to Run Locally"). The extensions load on the Mac that built them, and you don't need an Apple Developer account.

To sign with your own certificate, create `Config/Local.xcconfig`. This file is ignored by git.

```
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Apple Development
```

## Use

| Action | Result |
|---|---|
| Select a `.3mf` in Finder, press **Space** | 3D preview, spinning slowly until you touch it |
| Drag, or two-finger swipe on a trackpad | Rotate |
| Pinch | Zoom |
| Select a `.3mf` in Finder's column or gallery view, or with the preview pane open (⇧⌘P) | The same 3D preview in the side pane, spinning |
| Two-finger swipe over the preview pane | Rotate (click-drag in the pane drags the file instead; that's Finder's behavior) |
| Icon or list view in Finder | Plate image thumbnails |

Any click, swipe or pinch stops the auto-spin. Finder's file icons are static images. macOS only allows live, interactive content in the Quick Look panel and the preview pane.

## Supported files

| Source | What's read |
|---|---|
| Any 3MF (core spec) | Meshes, components, build-item transforms, `basematerials` and `colorgroup` colors |
| Bambu Studio / OrcaSlicer | Objects split across `3D/Objects/*.model`, per-object and per-part extruders (`model_settings.config`), filament colors (`project_settings.config`), multi-material paint (`paint_color`), plate thumbnails |
| PrusaSlicer | Volumes with their own extruders (`Slic3r_PE_model.config`), extruder and filament colors (`Slic3r_PE.config`), multi-material paint (`slic3rpe:mmu_segmentation`), `thumbnail.png` |

Painted triangles that the slicer subdivided are shown in the color that covers most of the triangle. This is accurate at normal viewing size. Very fine paint detail can look slightly softer than in the slicer.

## Troubleshooting

**Thumbnails or previews don't update.** Reset Quick Look and restart Finder:

```sh
qlmanage -r && qlmanage -r cache && killall Finder
```

**It stopped working after installing a slicer.** A slicer can declare its own file type for `.3mf`, and macOS may then send `.3mf` files to that type instead of this one. To see which type macOS uses:

```sh
swift -e 'import UniformTypeIdentifiers; print(UTType(filenameExtension: "3mf")!.identifier)'
```

If it doesn't print `com.designspiders.3mf`, add the printed identifier to `QLSupportedContentTypes` for both extensions in `project.yml`. Then run `make project install`. Pull requests that add identifiers for popular slicers are welcome.

**Check which extensions are registered:**

```sh
pluginkit -mAvvv | grep -A1 com.designspiders
```

## Uninstall

```sh
make uninstall
```

Or drag `3MF Preview.app` from `/Applications` to the Trash.

## Development

```sh
make test          # run the unit tests
make build         # release build into ./build
make install       # build and install to /Applications
make project       # regenerate 3MFPreview.xcodeproj from project.yml (brew install xcodegen)
make fixtures      # rebuild the synthetic test .3mf files
make render-test   # CLI tool: build/render-test <out-dir> file.3mf ... prints stats and writes PNG renders
```

`project.yml` is the source of truth for the Xcode project. The generated `3MFPreview.xcodeproj` is committed so you can build without XcodeGen. If you edit `project.yml`, run `make project` and commit both.

### Layout

```
App/          Host app: declares the .3mf file type and carries the extensions
Preview/      Quick Look preview extension (SceneKit view, Space bar)
Thumbnail/    Quick Look thumbnail extension (Finder icons)
Shared/       Code used by both extensions:
  ZipArchive.swift        minimal ZIP reader (stored, deflate, ZIP64)
  ThreeMFModel.swift      fast 3MF XML scanner, components, transforms, paint decoding
  SlicerSettings.swift    Bambu/Orca/Prusa extruder assignments and filament colors
  SceneBuilder.swift      flat-shaded SceneKit scene, lighting and camera
  ModelView.swift         preview view: auto-spin and trackpad-swipe orbiting
  PreviewSummary.swift    size and triangle-count caption
  SnapshotRenderer.swift  offscreen render for files without an embedded thumbnail
Tests/        XCTest suite and synthetic 3MF fixtures (Tests/Fixtures/make_fixtures.py)
Tools/        render-test command-line tool
Config/       Signing configuration
```

### How it works

A `.3mf` file is a ZIP package of XML. Model files can exceed 100 MB, so `ThreeMFModel` scans the raw bytes with a hand-written tag scanner instead of `XMLParser`. It then follows build items and components through any sub-model files and applies their transforms.

Each triangle's color is resolved in this order:

1. Paint state (filament *n*)
2. 3MF material
3. Volume extruder
4. Part extruder
5. Object extruder

The resulting extruder number is then looked up in the slicer's filament color list.

The preview flattens the mesh into one SceneKit geometry per color, with flat face normals so printed facets stay crisp. It converts the slicer's Z-up coordinates to SceneKit's Y-up.

## License

[MIT](LICENSE) © Dan Roose
