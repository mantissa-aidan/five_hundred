# Debug System Usage Guide

## Overview
The Debug system provides categorized logging to reduce console spam and focus on specific issues during development.

## Quick Start

### Enable Debug Categories
```lua
-- In main.lua or at the top of your file
local Debug = require "src.config.debug"

-- Enable specific categories
Debug:enable("ANIMATION")
Debug:enable("AUDIO")

-- Or enable all categories
Debug:enable_all()
```

### Using Debug Logging
```lua
local Debug = require "src.config.debug"

-- Simple message
Debug:log("ANIMATION", "Animation triggered")

-- Formatted message
Debug:log("ANIMATION", "intro_progress=%.3f", self.intro_progress)

-- Multiple arguments
Debug:log("AUDIO", "Playing %s from %s", sound_id, caller)
```

## Available Categories

| Category | Purpose | Default |
|----------|---------|---------|
| `AUDIO` | AudioManager play calls and sound loading | OFF |
| `ANIMATION` | General animation progress and state | OFF |
| `BIDDING_ANIM` | Specific to bidding UI animation | OFF |
| `CHAT_ANIM` | Chat panel slide animation | OFF |
| `GAME_STATE` | Game phase transitions (BIDDING, PLAYING, etc.) | **ON** |
| `DEAL` | Card dealing animation | OFF |
| `CARD_INTERACTION` | Drag/drop/click on cards | OFF |
| `BUTTON_INTERACTION` | Button hover/click events | OFF |
| `HOT_RELOAD` | Lurker hot-reload events | OFF |
| `LAYOUT` | UI layout calculations and resize | OFF |
| `TEST_VERBOSE` | Verbose test output | OFF |

## Command-Line Usage

You can enable debug categories from the command line:

```bash
# Enable specific category
love five_hundred_love --debug-animation

# Enable multiple categories
love five_hundred_love --debug-audio --debug-animation

# Enable all categories
love five_hundred_love --debug-all
```

To implement command-line support, add to `main.lua`:
```lua
function love.load(args)
    local Debug = require "src.config.debug"
    
    -- Parse command-line arguments
    for _, arg in ipairs(args) do
        if arg == "--debug-all" then
            Debug:enable_all()
        elseif arg:match("^--debug%-") then
            local category = arg:gsub("^--debug%-", ""):upper():gsub("%-", "_")
            Debug:enable(category)
        end
    end
    
    -- Rest of your load code...
end
```

## Examples

### Debugging Animation Issues
```lua
-- Enable animation logging
Debug:enable("ANIMATION")
Debug:enable("BIDDING_ANIM")

-- Your animation code will now log
-- [ANIMATION] intro_progress=0.161
-- [BIDDING_ANIM] Animation triggered
```

### Debugging Audio Problems
```lua
-- Enable audio logging
Debug:enable("AUDIO")

-- You'll see
-- [AUDIO] PLAYING: CARD_SLIDE (Card_Deal_4.wav) from update
-- [AUDIO] Warning: Sound not loaded: ALERT
```

### Quiet Console (Production)
```lua
-- Disable all debug output
Debug:disable_all()

-- Or just keep game state transitions
Debug:disable_all()
Debug:enable("GAME_STATE")
```

## Integration Checklist

When adding Debug logging to new code:

1. **Require Debug** at the top of your file:
   ```lua
   local Debug = require "src.config.debug"
   ```

2. **Replace print statements** with Debug:log:
   ```lua
   -- Before
   print("[MyModule] Something happened: " .. value)
   
   -- After
   Debug:log("MY_CATEGORY", "Something happened: %s", value)
   ```

3. **Add new category** to `src/config/debug.lua` if needed:
   ```lua
   Debug = {
       -- ... existing categories ...
       MY_CATEGORY = false,  -- Add your new category
   }
   ```

## Best Practices

1. **Use appropriate categories** - Don't log everything to GAME_STATE
2. **Keep messages concise** - Focus on actionable information
3. **Use formatting** - `Debug:log("CAT", "x=%.2f", x)` instead of string concatenation
4. **Default to OFF** - Only enable categories when debugging specific issues
5. **Document new categories** - Update this guide when adding categories

## Troubleshooting

**Q: My debug messages aren't showing**
- Check that the category is enabled: `Debug:print_config()`
- Verify the category name matches exactly (case-sensitive)

**Q: Too much output**
- Disable categories you don't need: `Debug:disable("AUDIO")`
- Or disable all and enable only what you need

**Q: Want to see everything**
- Use `Debug:enable_all()` but be prepared for lots of output!
