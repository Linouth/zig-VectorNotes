# zig-VectorNotes

Reimplementation of my C based [VectorNotes application](https://github.com/Linouth/VectorNotes).

A super simple note taking application using vector based drawing.

## Todo

Some lists for me to pick from when I want to work on this project.

### Essentials

- [x] Port my C program to Zig
- [x] Undo/Redo system
- [x] Better tools implementation
- [x] Selection tool
- [x] Optimize selection (prevent checks if user is zoomed in far)
- [ ] Deletion tool
- [x] Map 0 to 1 parameters to a whole bezier Path and evaluate the path
- [ ] Only render paths in view
- [x] Don't render paths zoomed out too far
- [ ] Save/load system
- [ ] Extract NanoVG wrapper into a separate library
- [ ] Proper memory error handling... (Get rid of `catch unreachable`)
- [ ] Squash memory leaks
- [ ] Minimal UI
- [ ] Better bounds calc for bezier paths
- [ ] Update Path interface
    - [x] Refactor Path and Canvas systems
    - [x] Eval for different path types (System is in place, specific eval
      functions not yet)
    - [ ] New draw system for paths

### Bugs

- [ ] `Path.eval` does not work correctly when zoomed in far. (add scaling to
  counter float errors?)
- [ ] Fitting algo
    - [ ] Fix bug that results in a bunch of segments very close to one another
    - [ ] Fix bug where a point is sometimes placed somewhat randomly, sometimes
      very far away
    - [ ] The fit shifts what seems like a contant amount when zoomed in far
- [ ] Selection failure; Sometimes a selection that should work, does not select
  the path.

### Future

- [ ] PDF viewer
- [ ] Export to different file formats
- [ ] Custom vector drawing library, with support for variable stroke widths
