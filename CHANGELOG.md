# Changelog

All notable changes to this project will be documented in this file.

## [1.0.7] - 2026-11-12

### Changed
- Picks up game-common 1.16.0: games for two readers (new Two readers
  category) and the shared Start / Join dialog.

## [1.0.6] - 2026-11-05

### Fixed
- On 5×5, Medium was as hard as Hard (about 10 presses both). Medium now
  needs 6–7 presses and Hard 12–14 (Easy stays at 4). Other sizes are
  unchanged. This changes the 5×5 Medium and Hard puzzles a seed gives,
  so a 5×5 Daily Challenge differs once.

## [1.0.5] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.0.4] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.

## [1.0.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.0.2] - 2026-11-02

### Changed
- Picks up game-common 1.10.0: the shared Tools → Games menu also lists
  the games' new "· multiplayer" entries under Party & quiz.

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-10-30

### Added
- First release: Lights Out on 5×5 to 9×9 grids, three difficulty levels.
- GF(2) solver: optimal press count for every puzzle, a Hint that follows an
  optimal solution, and Show solution rings.
- Undo, Restart, move counter, best per size and difficulty, auto-save.
  French translation.
