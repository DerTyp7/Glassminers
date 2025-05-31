## 0.1.2 (unreleased)

- Added some basic dust particles around the level
- Added some basic lava particles
- Added some basic particle effects when digging
- Added some basic particle effect when taking damage
- Improved the logging behavior of client & server
- Improved the lingering problem *again*. You should (^^) now always get a game over screen.

## 0.1.1 (30.05.2025)

- Implemented for gamepad input on Linux
- Implemented for XBox Button Icons for input binding hints
- Implemented a simple version check between client & server to avoid mismatches
- Implemented a cheat menu for developers to get coins, health or strength
- Implemented a limit to how many objects can be pushed at once by a guy
- Implemented pausing the game (on the server & all clients) if any client has the pause menu open
- Improved the lingering of virtual connections to less likely drop crucial information (like client disconnect, game over)
- Improved the error handling when a local server couldn't be started
- Fixed a crash when two players dig at the same entity
- Fixed a crash when the game ends with the emitter running out of time
- Fixed info messages in the main menu never disappearing
- Fixed the progress bar missing gaps in small window sizes
- Fixed missing error handling when any sprite index is not part of a sprite pack (for developers)
- Fixed a bug where other guys could be pushed out of lava (by walking into lava themselves)
- Fixed a missing input hint for turning a mirror if a guy is carrying an item

## 0.1.0 (25.05.2025)

This first prototype includes:

- A client/server architecture for online multiplayer. Both services can be included in the same executable for easier local playing.
- Keyboard input on linux & windows as well as gamepad input on windows
- A first working game loop including: Emitters, Mirrors & Receivers, Goblins & Frogs as Monsters, a Trader, Crystals, Rocks & Coal, Bedrock & Lava
