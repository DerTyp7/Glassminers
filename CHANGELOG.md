## 0.3.1 (unreleased)

- Sounds are now spatialized relative to the screen-center instead of the player position
- The tutorial was reworked to have multiple sections and explain more of the new mechanics. It can now be completed by placing the flag on the rightmost tile of the tutorial world
- Added a ghost mode cheat that enables players to walk through walls, monsters, etc
- Added a simple debug sound hud for developers
- Improved the probability of traders appearing in randomly generated worlds
- Flags can now only be placed on tiles where no move-blocking entity is (previously an exception was made for living entities)
- Fixed a bug where the camera would start interpolating between areas late
- Fixed a bug where new entities might be generated in previous sections when resizing the world
- Fixed a bug where emitters wouldn't be considered complete if they weren't the ones powering the latest emitter
- Fixed a bug where tabbing out the window wouldn't stop the current input action (such as digging)
- Fixed a bug where the hud would always select an option on opening on linux
- Fixed a crash on certain linux distributions that have a weird ALSA configuration

## 0.3.0 (27.07.2025)

The game design has been updated to no longer have one discrete goal; instead the goal is to come as far as possible. This is indicated by a new score mechanism. This score is driven by the furthest position the new flag entity has been placed on by a player. The world is now also growing infinitely large - as long as the latest emitter (acting as a checkpoint) has been powered up using a previous emitter.
    The flag is spawned once in a new world and can be picked up and placed down like regular items. It is therefore the players' job to make a safe path forward through the world to later carry the flag forward, to increase their score.
    The receiver entity has been completely removed.
    The emitter entity now acts as a gate between sections of the world, and can be powered up using beams. Once an emitter is powered up, the next part of the world will be generated. An emitter that has been powered up will always stay powered on and no longer requires coal intake.

- Implemented a spectator mode when a player is dead - Use the regular movement inputs to switch the player to spectate
- Implemented a simple developer panel for debugging purposes
- Improved the spatialization feel of sounds
- Fixed the sound channels being the wrong way around on linux
- Fixed the controller rumbling when guys were attacked while already being dead
- Fixed the font size not being off on linux
- Fixed some artifacts when drawing some icons or texts
- Fixed drawing the items that guys are carrying over the beams

## 0.2.3 (29.06.2025)

The previous changes apparently introduces a lot of regressions, which shall be fixed with this release.
It also attempts to improve the user experience of the game.

- Implemented gamepad vibration + color setting for local players when their health changes / they're digging. Note: Because every gamepad vendor is just an asshole, there's support limitations:
    - Rumble + LED on wired PS controllers on Windows
    - Rumble on wired XBox controllers on Windows
    - Rumble on wired XBox + PS controllers on Linux
    - No Rumble on bluetooth controllers on Linux or Windows
    - No LED on XBox controllers on Windows or any controllers on Linux
- Implemented "repeating" input actions: When holding down movement inputs, the guy will now continuously walk
- Implemented cursor input for the hud: You can drag the mouse or use the left stick on a gamepad to select an option in the hud wheel
- Changed the key binding for opening the crafting hud to E from Shift
- Changed the digging interaction from toggle to hold
- Holding down Shift while pressing WASD will now just rotate the player instead of moving
- Limited the slime's action radius to 8 blocks away from its nearest slime hole, so that slimes aren't too annoying across the entire world
- Added a stone dropping when destroying a chest
- Added a sound effect when the receiver is charging up
- Fixed the slider button for the volume setting disappearing sometimes
- Fixed the game ending when one player dies while having more than one local players
- Fixed the guy never switching away from the Death animation after having been resurrected
- Fixed the current action of a guy (digging, resurrecting) not being cancelled when being pushed by someone else
- Fixed wrongly cancelling the current action of a guy when failing to move
- Fixed a crash caused by being able to place torches out of bounds

## 0.2.2 (21.06.2025)

The world is now lit up (or rather darkended out) in areas where no light reaches. Light can come from beams and torches. This has a big effect on gameplay, as you can no longer see large parts of the world.

Also implemented spatialization for sounds. This means sounds that are further away will be more quiet. If there's only one local player, the sounds will also come from left or right channels.

- Implemented animations when a goblin, guy, frog, slime is hurt
- Implemented canceling the current digging by primary-interacting again
- Slightly changed the layout of the tutorial level
- Added cheats to spawn monsters, traders, as well as shard and stone items, and to make the player invincible
- Added particle effects to torches
- Added sound effects to the slime entity
- Fixed not being able to craft torches when the target tile is not empty
- Fixed one input bindings sometimes causing multiple actions in the same frame
- Fixed missing input hints for interacting with torches and chests
- Fixed being able to throw away items into slime holes
- Fixed only one slime fitting into a slime hole
- Fixed filled slime holes blocking guy movement
- Fixed being able to craft onto slime holes

## 0.2.1 (14.06.2025)

- Implemented a new slime enemy. Slimes will try to steal items laying on the ground while running aways from players.
- Implemented a torch entity that can be crafted from coal and can be picked up and placed down
- Implemented a chest entity into which up to 8 items can be put, to be safe from the slime.
- Made the direction from source to result clearer in the crafting menu
- Man-Made creations will now automatically restore health while not actively being destroyed, so that accidentally destroying them is less likely
- Fixed stuff spawning directly in front of the emitter
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
