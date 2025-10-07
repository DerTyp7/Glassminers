The game uses a lot of different sprites, which are authored in `Aseprite`.
We now want an easy and extendible way of matching the sprite identifiers used in the code together with the source file of the actual sprites that were drawn by our artist.
This is done in the sprite pack file.

Additionally, we also want to combine different sprites into animations, and animation groups.
Here's a quick definition of terms:
- A sprite is an image, basically a group of pixels. This sprite can be encoded as a PNG, or part of an `aseprite` file. Each sprite has a unique identifier in the game.
- An animation is a collection of sprites, and some additional metadata (most importantly the frame time, but also whether it is looping, etc). This animation also has a unique identifier in the game, and an entity stores which animation it is currently playing (along with the offset in that animation).
- An animation group maps each direction (north, south, east, west) to exactly one animation. This group also has a unique identifier in the game. This can be used to bundle all four walking animations (forward, backwards, side...) into a single identifier. The game code can then request to play one animation out of this group, depending on the entities current rotation.

## Asesprite File Format

## Sprite Pack File Format