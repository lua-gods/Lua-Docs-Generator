### Made with [LÖve](https://love2d.org/)


# Notes
* This Love2D Project was made specifically for [GNUI](https://github.com/lua-gods/GNUI) and for future libraries made by the [Lua Goofs](https://github.com/lua-gods/).
* Its made though love2D because its the only thing I (GNamimates) knew at the time.
* This Project is heavily biased towards my annotation structure.

# How to use
simply dump your scripts into a folder called `src` in the same place as where `main.lua` is  
once ran its gonna output at `%appdata%/LOVE/<root-folder-name>/`

# How it works
1. Gathers every file into one long table of lines
1. Scrapes all the classes and its fields into a table
1. Srapes all the methods/functions and pairs them to their given classes
1. Generates a file for each class declared in all files
1. Creates a table of contents into the `_Sidebar.md`
1. Ding!

# Limitations / Reqirements
### The Annotation must be made though Summeko Lua format 
### Class and Function Pairing
the class declaration must have a local variable declared at the last line

```lua
---@class Box           
---@field Size : Vector3
local box_methods = {}
```
Every method/functon applied into the `box_methods` local variable gets assigned to be in the `Box` class.

# Examples
[lua-gods/GNUI](https://github.com/lua-gods/GNUI)
