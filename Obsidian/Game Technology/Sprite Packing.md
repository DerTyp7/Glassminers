The game uses a lot of different sprites, which are authored in `Aseprite`.
We now want an easy and extendible way of matching the sprite identifiers used in the code together with the source file of the actual sprites that were drawn by our artist.
This is done in the sprite pack file.

Additionally, we also want to combine different sprites into animations, and animation groups.
Here's a quick definition of terms:
- A sprite is an image, basically a group of pixels. This sprite can be encoded as a PNG, or part of an `aseprite` file. Each sprite has a unique identifier in the game.
- An animation is a collection of sprites, and some additional metadata (most importantly the frame time, but also whether it is looping, etc). This animation also has a unique identifier in the game, and an entity stores which animation it is currently playing (along with the offset in that animation).
- An animation group maps each direction (north, south, east, west) to exactly one animation. This group also has a unique identifier in the game. This can be used to bundle all four walking animations (forward, backwards, side...) into a single identifier. The game code can then request to play one animation out of this group, depending on the entities current rotation.

## Aseprite File Format
For the official documentation of the file format, visit [github.com/aseprite](https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md#chunk-types). This paragraph just serves as a quick overview of how the Aseprite parser was actually implemented.

- An ``Aseprite`` file consists of a file header and a number of frames
- Each frame consists of a header and a number of chunks
- Each chunk consists of a header and some content. There's a number of different chunks, for example:
	- **Layer chunk**: Contains information about a single layer, e.g. what kind of layer, some flags, the blend mode...
	- **Cel chunk**: Contains actual pixel data that should be put into a layer / frame. There's again different types of cel chunks, which encode the pixel data in different ways (i.e. raw rgba or index into palette)
	- **Palette Chunk**: Contains a number of colors that can be indexed from other chunks
	- ...
- The first frame usually stores the "global" metadata as chunks, which also apply to other frames as well.
- The parser iterates over the file to find all frames and layers, and then does a second iteration to actually read the binary data.
- The parser returns a struct that contains the dimensions of the images in pixels, as well as a list of the layers and frames in each layer.

## Sprite Pack File Format
This file shall be able to encode all three of the mentioned asset types: Sprites, animations and animation packs.
This means we have only a single file that needs to be maintained, and it's easy to see how and where different sprites are used and combined. 
Nevertheless it should also be possible to merge multiple files in the Sprite Pack File Format into one. This could be interesting when trying to automate part of the process, in which case we might have one hand-edited and one generated sprite pack file or something.

I imagine the following syntax for the sprite pack file, just giving an example:
```
#
# Sprite List
#

# SPRITE <Sprite Identifier>   <Source File Path>   [Frame Index [Layer Name]];

SPRITE Guy_Idle_Back_0   aseprite/guy/guy-idle.aseprite 0 Back;
SPRITE Guy_Idle_Back_1   aseprite/guy/guy-idle.aseprite 1 Back;
SPRITE Guy_Idle_Front_0  aseprite/guy/guy-idle.aseprite 0 Front;
SPRITE Guy_Idle_Front_1  aseprite/guy/guy-idle.aseprite 1 Front;
SPRITE Guy_Idle_Side_0   aseprite/guy/guy-idle.aseprite 0 Side;
SPRITE Guy_Idle_Side_1   aseprite/guy/guy-idle.aseprite 1 Side;

SPRITE Lava pngs/animates/lava-0.png;

#
# Animation List
#

# ANIMATION <Animation Identifier> <Frame Time> <Flags...> FRAMES <Sprite Ident List...>;
ANIMATION Guy_Idle_Back 0.15 loop is_idle FRAMES
	Guy_Idle_Back_0
	Guy_Idle_Back_1;
	
ANIMATION Guy_Idle_Front 0.15 loop flip is_idle FRAMES
	Guy_Idle_Front_0
	Guy_Idle_Front_1;
	
ANIMATION Guy_Idle_Side 0.15 loop is_idle FRAMES
	Guy_Idle_Side_0
	Guy_Idle_Side_1;
	
#
# Animation Group List
#

# GROUP <Group Identifier> [(<Direction> <Animation Ident>)...];

GROUP Guy_Idle NORTH Guy_Idle_Back SOUTH Guy_Idle_Front EAST Guy_Idle_Side WEST Guy_Idle_Side;
```
