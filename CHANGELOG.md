## 0.2.2 (unreleased)

The world is now lit up (or rather darkended out) in areas where no light reaches. Light can come from beams and torches. This has a big effect on gameplay, as you can no longer see large parts of the world.

- Started implementing animations when creatures are being damaged
- Slightly changed the layout of the tutorial level
- Added cheats to spawn monsters, traders, as well as shard and stone items, and to make the player invincible
- Added particle effects to torches
- Fixed not being able to craft torches when the target tile is not empty
- Fixed one input bindings sometimes causing multiple actions in the same frame
- Fixed missing input hints for interacting with torches

## 0.2.1 (14.06.2025)

- Implemented a new slime enemy. Slimes will try to steal items laying on the ground while running aways from players.
- Implemented a torch entity that can be crafted from coal and can be picked up and placed down
- Implemented a chest entity into which up to 8 items can be put, to be safe from the slime.
- Made the direction from source to result clearer in the crafting menu
- Man-Made creations will now automatically restore health while not actively being destroyed, so that accidentally destroying them is less likely
- Prevented stuff to spawn directly in front of the emitter
- Fixed the viewport calculation when the width is smaller than the height
- Fixed the visual position interpolation when experiencing frame drops
- Fixed the size of the crafting menu hud being way too large when playing on small-width viewports
- Fixed a sporadic crash when particle systems were cleaned up unexpectedly (e.g. because of frame time spikes)
- Fixed the "Continue" button in the pause menu not resuming the game on the server
- Fixed the server not stopping when the last player disconnects during a game pause

## 0.2.0 (08.06.2025)

Support for local multiplayer! Each client can now support up to 4 local players, which still talk to the server as before. This means you can mix and match local and online multiplayer.
    This also means that you can now have up to 4 gamepads connected. Each local player (that uses gamepad input) will use a different gamepad for input.
    This required quite a lot of changes in the server and the client to get working, so it's a breaking change, but one that I'm very happy with.

Support for our new internal animation file format! This is only relevant for the development process, but it should make it much nicer to structure sprite animations, because I no longer have to hardcode animations in one specific place.

Some minor improvements are also included:
- Added sensical defaults to all main menu options
- The main menu options are now restored after connecting & disconnecting
- The local player setup (names and input devices) are restored between games
- Background tiles are now visibility culled
- Particle Emitters are now visibility culled
- The target rectangle's thickness is now scaled to the viewport size
- Prevented the client from spamming game start requests when using the "single player" option in the main menu
- Tried to improve the feeling of the light beam flickering
- Added a cheat to get a coal item
- The selected option in crafting menus now tries to stay persistent if possible, and avoids junky animations

## 0.1.2 (31.05.2025)

- Added some basic dust particles around the level
- Added some basic lava particles
- Added some basic particle effects when digging
- Added some basic particle effect when taking damage
- Added some basic particle effect when healing
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
