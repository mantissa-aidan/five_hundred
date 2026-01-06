-- ModifierRegistry.lua
-- Registry of all available modifiers (templates)

local Modifier = require "src.core.modifier"

local ModifierRegistry = {}
ModifierRegistry.modifiers = {}

-- Register a modifier template
function ModifierRegistry.register(config)
    local mod = Modifier.new(config)
    ModifierRegistry.modifiers[mod.id] = mod
    return mod
end

-- Get a modifier template by ID
function ModifierRegistry.get(id)
    return ModifierRegistry.modifiers[id]
end

-- Create a new instance of a modifier
function ModifierRegistry.create(id)
    local template = ModifierRegistry.modifiers[id]
    if template then
        return template:clone()
    end
    return nil
end

-- Get all modifiers of a specific type
function ModifierRegistry.get_by_type(mod_type)
    local result = {}
    for _, mod in pairs(ModifierRegistry.modifiers) do
        if mod.type == mod_type then
            table.insert(result, mod)
        end
    end
    return result
end

-- Get all modifiers of a specific rarity
function ModifierRegistry.get_by_rarity(rarity)
    local result = {}
    for _, mod in pairs(ModifierRegistry.modifiers) do
        if mod.rarity == rarity then
            table.insert(result, mod)
        end
    end
    return result
end

-- Get list of all modifier IDs
function ModifierRegistry.get_all_ids()
    local ids = {}
    for id, _ in pairs(ModifierRegistry.modifiers) do
        table.insert(ids, id)
    end
    return ids
end

-- ============================================
-- MODIFIER DEFINITIONS
-- ============================================

-- SCORING MODIFIERS --

ModifierRegistry.register({
    id = "ace_boost",
    name = "Ace Master",
    description = "Aces worth 2x points",
    type = Modifier.TYPE.SCORING,
    category = Modifier.CATEGORY.CARD_BOOST,
    rarity = Modifier.RARITY.COMMON,
    icon = "A",
    color = {1, 0.9, 0.3},
    effect = function(ctx, value, self)
        if ctx.card and ctx.card.rank == 14 then  -- Ace
            return value * 2
        end
        return value
    end
})

ModifierRegistry.register({
    id = "joker_master",
    name = "Joker Master",
    description = "Joker worth 3x points",
    type = Modifier.TYPE.SCORING,
    category = Modifier.CATEGORY.CARD_BOOST,
    rarity = Modifier.RARITY.RARE,
    icon = "J",
    color = {1, 0.3, 0.3},
    effect = function(ctx, value, self)
        if ctx.card and ctx.card.rank == 100 then  -- Joker
            return value * 3
        end
        return value
    end
})

ModifierRegistry.register({
    id = "trump_master",
    name = "Trump Master",
    description = "Trump cards worth 1.5x points",
    type = Modifier.TYPE.SCORING,
    category = Modifier.CATEGORY.CARD_BOOST,
    rarity = Modifier.RARITY.COMMON,
    icon = "T",
    color = {0.3, 0.8, 1},
    effect = function(ctx, value, self)
        if ctx.is_trump then
            return value * 1.5
        end
        return value
    end
})

ModifierRegistry.register({
    id = "bower_bonus",
    name = "Bower Bonus",
    description = "Bowers worth 3x points",
    type = Modifier.TYPE.SCORING,
    category = Modifier.CATEGORY.CARD_BOOST,
    rarity = Modifier.RARITY.RARE,
    icon = "B",
    color = {0.8, 0.2, 0.8},
    effect = function(ctx, value, self)
        if ctx.is_bower then
            return value * 3
        end
        return value
    end
})

ModifierRegistry.register({
    id = "high_roller",
    name = "High Roller",
    description = "Face cards (J/Q/K) worth 2x points",
    type = Modifier.TYPE.SCORING,
    category = Modifier.CATEGORY.CARD_BOOST,
    rarity = Modifier.RARITY.COMMON,
    icon = "H",
    color = {1, 0.6, 0.2},
    effect = function(ctx, value, self)
        if ctx.card and ctx.card.rank >= 11 and ctx.card.rank <= 13 then
            return value * 2
        end
        return value
    end
})

ModifierRegistry.register({
    id = "streak_master",
    name = "Streak Master",
    description = "Streak multipliers +50% more effective",
    type = Modifier.TYPE.SCORING,
    category = Modifier.CATEGORY.STREAK,
    rarity = Modifier.RARITY.EPIC,
    icon = "S",
    color = {0.2, 1, 0.5},
    effect = function(ctx, value, self)
        -- This modifier enhances streak multipliers
        -- Applied at trick scoring level
        if ctx.streak_multiplier and ctx.streak_multiplier > 1 then
            local bonus = (ctx.streak_multiplier - 1) * 0.5
            return value * (1 + bonus)
        end
        return value
    end
})

ModifierRegistry.register({
    id = "trick_bonus",
    name = "Trick Bonus",
    description = "+1000 base points per trick",
    type = Modifier.TYPE.SCORING,
    category = Modifier.CATEGORY.MULTIPLIER,
    rarity = Modifier.RARITY.COMMON,
    icon = "+",
    color = {0.5, 1, 0.5},
    effect = function(ctx, value, self)
        if ctx.is_trick_scoring then
            return value + 1000
        end
        return value
    end
})

ModifierRegistry.register({
    id = "contract_king",
    name = "Contract King",
    description = "Contract bonuses worth 2x",
    type = Modifier.TYPE.SCORING,
    category = Modifier.CATEGORY.MULTIPLIER,
    rarity = Modifier.RARITY.EPIC,
    icon = "C",
    color = {1, 0.8, 0.3},
    effect = function(ctx, value, self)
        if ctx.is_contract_scoring then
            return value * 2
        end
        return value
    end
})

-- SNAP MODIFIER (Passive) --

ModifierRegistry.register({
    id = "snap_bonus",
    name = "Snap!",
    description = "10x points when you match partner's rank",
    type = Modifier.TYPE.SPECIAL,
    category = Modifier.CATEGORY.SNAP,
    rarity = Modifier.RARITY.LEGENDARY,
    icon = "!",
    color = {1, 1, 0},
    effect = function(ctx, value, self)
        -- Snap is checked at trick completion
        if ctx.snap_triggered then
            return value * 10
        end
        return value
    end
})

-- NEGATIVE MODIFIERS --

ModifierRegistry.register({
    id = "low_card_curse",
    name = "Low Card Curse",
    description = "Cards below 9 worth 50% less",
    type = Modifier.TYPE.NEGATIVE,
    category = Modifier.CATEGORY.DOWNGRADE,
    rarity = Modifier.RARITY.COMMON,
    icon = "-",
    color = {0.5, 0.2, 0.2},
    effect = function(ctx, value, self)
        if ctx.card and ctx.card.rank < 9 then
            return value * 0.5
        end
        return value
    end
})

return ModifierRegistry
