![TabRewind](assets/tabrewind.svg)

**Simple problem.** Safari’s **Control-Tab** moves to the next tab in the bar. Getting back to the tab you just used should be just as easy.

**Even simpler solution.** Press **Control-Tab** to jump to your last-used tab. Keep holding **Control** and tap **Tab** to cycle through the rest in order of recent use.


## Install

Download the universal app from [GitHub Releases](https://github.com/LDenninger/safari-tab-rewind/releases/latest).

To build from source on a Mac with the Xcode Command Line Tools, run:

```sh
git clone https://github.com/LDenninger/safari-tab-rewind.git
cd safari-tab-rewind
./install.sh
```

The script builds and locally signs the app, installs it in `~/Applications`, and opens it. The app targets macOS 13 and newer. Its browser integration was tested on Safari 27.

If macOS asks, enable **TabRewind** in **System Settings → Privacy & Security → Accessibility**. The app’s settings also show **Grant Accessibility…** when permission is needed.

## Settings

Reopen **TabRewind** from Finder or Spotlight while it is running to show its settings. The menu bar icon is hidden by default. Turn on **Show in Menu Bar** if you want quick access there.

Click the current shortcut and press a new combination to change it. Include Control, Option, or Command. Press **Escape** to cancel, or click **Restore Default** to return to Control–Tab. **Start at Login** is optional.

## How it works

The app registers the shortcut with macOS while Safari is active. Each Safari window has its own recent-tab history. The shortcut cycles through tabs in the active window using Safari's accessibility controls. Tabs that haven't been visited since the app started come after the known tabs, in tab-bar order. The history starts fresh when the app is relaunched. It stores accessibility element references in memory and saves the shortcut locally. It has no network access code and reads no page content.

A native helper lets Control–Tab work from browser chrome as well as from webpages. Safari's extension commands and page scripts do not provide the same browser-wide shortcut. The helper relies on Safari's accessibility hierarchy, which can change between Safari versions.

## Update or remove

To update, quit from the settings window, pull the latest source, and run `./install.sh` again. If **Grant Accessibility…** still appears after rebuilding, remove the old entry in the Accessibility permissions list and add the rebuilt app from `~/Applications`.

To remove, turn off **Start at Login** if enabled, quit TabRewind, and move `~/Applications/TabRewind.app` to the Trash.
