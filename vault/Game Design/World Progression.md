One of the most important parts of balancing the game will be the progression inside the world.
This includes a few key notes:
- The change of difficulty over the previous sections
- The change in gameplay mechanics
- The change of visuals

# Difficulty Progression
## Why we need difficulty progression
If a run in the game has the same (perceived) difficulty over its entire duration, the game will probably be boring. It will feel like the players have already seen everything after the first few minutes, leading to boredom. It also means that you will probably either not manage at all and die in the first sections, or they will just go infinitely long.

The change in difficulty is also really important for the players to stay in the flow state. The longer the game goes, the more resources the players can build up (take from the previous sections), the better they get at communicating and at the game in general. Therefore, it is only natural that the difficulty should increase as the skill increases to stay in the flow state.

Finally, increasing the difficulty is important for a natural end of the game, and the feeling of improvement over several runs. If the difficulty stays constant, it is basically up to the patience of players and a lot of luck how far they get. If the difficulty increases, how far you get is much more influenced by the actual game. You can then compare how far you got over the last few runs, and at the same time the game will end when you reached your "skill ceiling".

The change in difficulty also breaks up the repetitiveness of the game. If the game gets a lot harder over a couple of sections, and then drops in difficulty again, that breaks a pattern and leads to a more interesting progression. It can lead to the players tensing up for a while and then relaxing for a few sections afterwards, leading to a feeling of progression and reward.

## How to implement difficulty progression
There's some knobs we can turn for tuning the difficulty, mostly related to world generation:
- The spawn rate of monsters / lava / bedrock
- The spawn rate of traders / resources
- The drop rate of coins
- The maximum duration of emitters
- The charge per coal item
- The length of each section

For these values, we roughly want to increase their difficulty in a curve, but with some pattern-breaking. This means instead of a monotonic curve we want to increase these difficulties for a while, and then decrease them again for some tense-and-release.

However, all of these values can only be changed in a certain range, as the game quickly becomes impossible otherwise (imagine the charge per coal item going towards zero...).
Also, these must change somewhat insignificantly per section to still be playable, so the player might not notice that these values actually change...

Therefore, we would also like to have more ways of tuning the difficulty.
- [[Biomes]] can have concrete challenges that the player will definitely notice. These challenges have different aspects of what make them difficult to solve (e.g. requires a lot of resources, has puzzle-like elements, has time pressure...)
- Increasing the cost of recipes at [[Trader]]s will increase the difficulty naturally, as more monsters need to be killed to gather crucial resources or other benefits. If the cost increases with the number of transactions done, this is a very natural difficulty progression
- Reducing the health of players (temporarily) can increase the pressure on players as they can make fewer mistakes, or it requires more calculation and precision to execute some moves (when calculating to take damage)


# Change in Gameplay Mechanics
Our gameplay mechanics are pretty monotonous during the game. Breaking the pattern of what you are actually expected to do to solve a section can help with that and make the game more interesting to play.
- One way of implementing this is again through different [[biomes]]. Each biome can require a unique way of solving it, breaking away from the usual game loop and instead breaking into a puzzle or action based game for while.

# Change in Visuals
Another way of breaking the repetitiveness is just changing the visuals and the narrative.
By simply changing the surroundings from a mine to some fantasy world or some other thing, the player might get a fresh start to how the game feels.
They will also be interested in what has changed (even if just visual) and therefore have a motivation to keep playing.
This change in visuals can also act as a progression point - for example it can be a reward to reach the "cloud part" of the game.