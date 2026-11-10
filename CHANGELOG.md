## Main changes
- Version: 0.17.3
- Interface: **Every picker opens where it was last used** - the desktop file and folder pickers each remember their own folder, so firmware archives start in Downloads and images in Pictures instead of nine of the ten pickers opening wherever the system put them, which on Linux is often the root; a folder that has since been deleted falls back to one that exists rather than to nothing, and Android and iOS keep using the system's own memory (by @apfxtech | PR #488)
## Other changes
- Fixed: on an Intel Mac animations tore into diagonal triangles and random letters in text were replaced by stray symbols, because Flutter 3.47 made Impeller the default macOS renderer and it draws incorrectly on Intel graphics; those Macs render with Skia again, as every Mac did before 3.47, while Apple silicon keeps Impeller and is unaffected (by @apfxtech | PR #487)
