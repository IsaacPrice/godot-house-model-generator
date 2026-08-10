# Example houses

Test fixtures used while developing the plugin. They are here so the tool has
something to open on a fresh clone, and so the save/load format stays exercised.
They are not finished art and are not intended for use in a game as-is.

Open any of them through the House Builder dock's **Open** button.

| File | What it is |
| --- | --- |
| `LargerHouse.tscn` | Two floors, porch, sidewalk and driveway, dormers, chimney, gutters. The most complete example. |
| `SmallHouse.tscn` | Two floors with a porch, 18 cells. Small enough to read the whole grid at a glance. |
| `template.tscn` | Nearly empty. A blank house with default geometry constants, useful as a starting point. |

## File format

A saved house is a single `.tscn` — the exported, instantiable scene with the
editable `HouseData` embedded as `house_data` metadata on the root node. Saving
is exporting; there is no separate step.

`HouseFile.load_any` also still reads the older standalone `HouseData` `.tres`
format, so opening one and saving it produces the combined `.tscn`.
