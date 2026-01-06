-- Modifier.lua
-- Base class for all modifiers/powerups in roguelike mode

local Utils = require "src.core.utils"

local Modifier = Utils.class("Modifier")

-- Modifier Types
Modifier.TYPE = {
    SCORING = "SCORING",         -- Affects point calculations
    DECK_DEAL = "DECK_DEAL",     -- Affects card distribution
    CARD_STRENGTH = "CARD_STRENGTH", -- Affects trick winning
    SPECIAL = "SPECIAL",         -- Unique effects
    NEGATIVE = "NEGATIVE",       -- Debuffs/challenges
}

-- Modifier Categories
Modifier.CATEGORY = {
    CARD_BOOST = "CARD_BOOST",   -- Boost specific cards
    MULTIPLIER = "MULTIPLIER",   -- General multipliers
    STREAK = "STREAK",           -- Streak bonuses
    SNAP = "SNAP",               -- Snap mechanic
    GUARANTEE = "GUARANTEE",     -- Guarantee certain cards
    DOWNGRADE = "DOWNGRADE",     -- Weaken opponents
}

-- Rarity levels (affects drop rates and power)
Modifier.RARITY = {
    COMMON = "COMMON",           -- 60% of drops
    RARE = "RARE",               -- 25% of drops
    EPIC = "EPIC",               -- 12% of drops
    LEGENDARY = "LEGENDARY",     -- 3% of drops
}

-- Expiration types
Modifier.EXPIRES_ON = {
    NEVER = "NEVER",             -- Permanent until discarded
    TRICK = "TRICK",             -- Expires after N tricks
    ROUND = "ROUND",             -- Expires after N rounds
}

function Modifier:init(config)
    -- Core identity
    self.id = config.id or "unknown"
    self.name = config.name or "Unknown Modifier"
    self.description = config.description or ""

    -- Classification
    self.type = config.type or Modifier.TYPE.SCORING
    self.category = config.category or Modifier.CATEGORY.MULTIPLIER
    self.rarity = config.rarity or Modifier.RARITY.COMMON

    -- Duration
    self.duration = config.duration  -- nil = permanent
    self.expires_on = config.expires_on or Modifier.EXPIRES_ON.NEVER
    self.remaining = config.duration  -- Countdown for expiring modifiers

    -- Effect function (called during scoring/gameplay)
    self.effect = config.effect or function(context, value) return value end

    -- Visual
    self.icon = config.icon or "?"
    self.color = config.color or {1, 1, 1}
end

-- Apply the modifier's effect
-- context: varies by modifier type (card info, trick info, etc.)
-- value: the base value being modified
function Modifier:apply(context, value)
    if self.effect then
        return self.effect(context, value, self)
    end
    return value
end

-- Check if modifier applies to a given context
function Modifier:applies_to(context)
    -- Override in specific modifiers for conditional application
    return true
end

-- Decrement duration counter
function Modifier:tick(tick_type)
    if self.expires_on == tick_type and self.remaining then
        self.remaining = self.remaining - 1
    end
end

-- Check if modifier has expired
function Modifier:is_expired()
    if self.expires_on == Modifier.EXPIRES_ON.NEVER then
        return false
    end
    return self.remaining and self.remaining <= 0
end

-- Get display color based on rarity
function Modifier:get_rarity_color()
    if self.rarity == Modifier.RARITY.COMMON then
        return {0.7, 0.7, 0.7}  -- Gray
    elseif self.rarity == Modifier.RARITY.RARE then
        return {0.3, 0.5, 1.0}  -- Blue
    elseif self.rarity == Modifier.RARITY.EPIC then
        return {0.8, 0.3, 0.8}  -- Purple
    elseif self.rarity == Modifier.RARITY.LEGENDARY then
        return {1.0, 0.8, 0.2}  -- Gold
    end
    return {1, 1, 1}
end

-- Create a copy of this modifier (for spawning from templates)
function Modifier:clone()
    return Modifier.new({
        id = self.id,
        name = self.name,
        description = self.description,
        type = self.type,
        category = self.category,
        rarity = self.rarity,
        duration = self.duration,
        expires_on = self.expires_on,
        effect = self.effect,
        icon = self.icon,
        color = self.color,
    })
end

-- String representation
function Modifier:__tostring()
    return string.format("[%s] %s (%s)", self.rarity, self.name, self.type)
end

return Modifier
