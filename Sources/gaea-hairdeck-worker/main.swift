import GaeaPluginKit
import HairDeckPlugin

// The plugin's worker: HairDeckPlugin's definition over GPP (GaeaPluginKit). `--manifest <path>` writes manifest.json.
await GaeaPluginMain.run(hairdeckPlugin)
