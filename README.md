# Safari Tab Recall

Press **Control–Tab** to jump to the last-used open tab in the current Safari window. Keep holding **Control** and tap **Tab** to keep moving through the tabs in most-recently-used order. Each step switches immediately without an overlay. Release Control to finish and make the selected tab the most recently used.

## Install

On a Mac with the Xcode Command Line Tools, run:

```sh
git clone https://github.com/LDenninger/safari-tab-recall.git
cd safari-tab-recall
./install.sh
```

The script builds and locally signs the app, installs it in `~/Applications`, and opens it. The app targets macOS 13 and newer. Its browser integration was tested on Safari 27.

If macOS asks, enable **Safari Tab Recall** in **System Settings → Privacy & Security → Accessibility**. The app’s settings also show **Grant Accessibility…** when permission is needed.

## Settings

Reopen **Safari Tab Recall** from Finder or Spotlight while it is running to show its settings. The menu bar icon is hidden by default. Turn on **Show in Menu Bar** if you want quick access there.

To change the shortcut, press the combination you want to use and click **Save**. The combination needs Control, Option, or Command. **Reset Shortcut** restores Control–Tab. **Start at Login** is optional.

## How it works

The app registers the shortcut with macOS while Safari is active. It uses Safari's accessibility tab controls to remember selected tabs in each window. Tabs that haven't been visited since the app started come after the known tabs, in tab-bar order. The history starts fresh when the app is relaunched. It stores accessibility element references in memory and saves the shortcut locally. It has no network access code and reads no page content.

A native helper lets Control–Tab work from browser chrome as well as from webpages. Safari's extension commands and page scripts do not provide the same browser-wide shortcut. The helper relies on Safari's accessibility hierarchy, which can change between Safari versions.

## Update or remove

To update, quit from the settings window, pull the latest source, and run `./install.sh` again. If **Grant Accessibility…** still appears after rebuilding, remove the old entry in the Accessibility permissions list and add the rebuilt app from `~/Applications`.

To remove, turn off **Start at Login** if enabled, quit Safari Tab Recall, and move `~/Applications/Safari Tab Recall.app` to the Trash.
