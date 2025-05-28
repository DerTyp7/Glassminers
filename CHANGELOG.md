## 0.1.1 (unreleased)

- Support for gamepad input on Linux
- Support for XBox Button Icons for input binding hints
- Improved the lingering of virtual connections to less likely drop crucial information (like client disconnect, game over)
- Fixed a crash when two players dig at the same entity
- Fixed a crash when the game ends with the emitter running out of time

## 0.1.0 (25.05.2025)

This first prototype includes:

- A client/server architecture for online multiplayer. Both services can be included in the same executable for easier local playing.
- Keyboard input on linux & windows as well as gamepad input on windows
- A first working game loop including: Emitters, Mirrors & Receivers, Goblins & Frogs as Monsters, a Trader, Crystals, Rocks & Coal, Bedrock & Lava
