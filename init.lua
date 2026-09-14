--[[

    ========================================================================
    Sieving for Mineclonia game in Luanti
    by Micu (c) 2026

    Copyright (C) 2026 Michal Cieslakiewicz

    v0.2, September 2026, basic Bucket Sieve added
    v0.1, September 2026, initial release

    License: LGPLv2.1+
    Media: CC BY-SA
    ========================================================================

--]]

-- ================
-- Config variables
-- ================

mcl_sieving = {}

local modname = core.get_current_modname()
--local S = core.get_translator(modname)
local S = function(s) return s end
local C = core.colorize
local F = core.formspec_escape

local SIEVE_TYPE_BUCKET = 1
--local SIEVE_TYPE_AUTO = 2
--local SIEVE_TYPE_ELEPOWER = 3

local PUNCHES_TO_SIEVE = 8

local sieve_liquid_container = {
    ["mcl_buckets:bucket_water"] = { empty = "mcl_buckets:bucket_empty" },
    ["mcl_buckets:bucket_river_water"] = { empty = "mcl_buckets:bucket_empty" }
}

-- Recipes
local sieve_recipe = {
    [SIEVE_TYPE_BUCKET] = {
        {
            input = "mcl_core:redsand", leftover = "mcl_core:sand",
            samples = 4,
            outputs = {
                ["mcl_core:iron_nugget"] = 2,
                ["mcl_raw_ores:raw_iron"] = 1,
            }
        },
        {
            input = "mcl_core:gravel", leftover = "mcl_core:sand",
            samples = 8,
            outputs = {
                ["mcl_core:gold_nugget"] = 3,
                ["mcl_raw_ores:raw_gold"] = 1,
            }
        }
    },
--    [SIEVE_TYPE_AUTO] = {}
--    [SIEVE_TYPE_ELEPOWER] = {}
}

-- TODO: for elepower use powders instead of raw ores

-- =============
-- Internal data
-- =============

-- Node names for node-swapping animations
local sieve_node_name = {
    [SIEVE_TYPE_BUCKET] = {
        [0] = "mcl_sieving:bucket_sieve",
        [1] = "mcl_sieving:bucket_sieve_2"
    },
--    [SIEVE_TYPE_AUTO] = {},
--    [SIEVE_TYPE_ELEPOWER] = {}
}

-- Speedup for node animations
local sieve_node_cycles = {}

-- Lookup table for allowed input check speedup
local allowed_inputs = {}

-- Lookup table for recipe processing speedup
-- [SIEVE_TYPE] = {
--   [input] = {
--      samples,
--      leftover,
--      products = { },
--      orequant = {
--          ore,
--          quantity_ge
--      }
--   }
-- }
local recipes_by_input = {}

-- ====
-- INIT
-- ====

for t, n in pairs(sieve_node_name) do
    sieve_node_cycles[t] = #n + 1   -- indexed from 0
end

-- Fill lookup tables based on current recipes
for t, s in ipairs(sieve_recipe) do
    allowed_inputs[t] = {}
    recipes_by_input[t] = {}
    for _, r in ipairs(s) do
        allowed_inputs[t][r.input] = true
        recipes_by_input[t][r.input] = { samples = r.samples, leftover = r.leftover, products = { r.leftover }, orequant = {} }
        local total_quantity = 0
        for o, n in pairs(r.outputs) do
            table.insert(recipes_by_input[t][r.input].products, o)
            table.insert(recipes_by_input[t][r.input].orequant, { ore = o, quantity_ge = total_quantity })
            total_quantity = total_quantity + n
        end
        table.insert(recipes_by_input[t][r.input].orequant, { ore = false, quantity_ge = total_quantity })
        table.sort(recipes_by_input[t][r.input].orequant, function (a, b) return a.quantity_ge > b.quantity_ge end)
    end
end

--core.debug("***** sieve_node_cycles = " .. dump2(sieve_node_cycles))
--core.debug("***** allowed_inputs = " .. dump2(allowed_inputs))
--core.debug("***** recipes_by_input = " .. dump2(recipes_by_input))

-- =================================
-- Node common callbacks and helpers
-- =================================

-- Simulate adding products to node inventory (multi-item version of default room_for_item())
local function room_for_items(inv, listname, itemlist)
    if inv:is_empty(listname) then return true end
    local lst = inv:get_list(listname)
    if not lst then return false end
    local shadow_inv = core.create_detached_inventory(modname .. "_room_check_inv", {})
    shadow_inv:set_size(listname, #lst)
    shadow_inv:set_list(listname, lst)
    for _, item in ipairs(itemlist) do
        local leftover = shadow_inv:add_item(listname, item)
        if not leftover:is_empty() then
            return false
        end
    end
    return true
end

-- Retrieve randomized sieved ore based on recipe for specific sieve type (or false for no luck)
local function get_random_ore(sieve_type, input)
    local rnd = math.random(0, recipes_by_input[sieve_type][input].samples - 1)
    for _, o in ipairs(recipes_by_input[sieve_type][input].orequant) do
        if rnd >= o.quantity_ge then return o.ore end
    end
    return false
end

-- Common callback for protection check before inventory take
local function check_inventory_take_protection(pos, _, _, stack, player)
    local playername = player:get_player_name()
    if core.is_protected(pos, playername) then
        core.record_protection_violation(pos, playername)
        return 0
    end
    return stack:get_count()
end

-- ============
-- BUCKET SIEVE
-- ============

-- --------
-- Formspec
-- --------

local function bucket_sieve_formspec(percent_complete)
    return table.concat({
        "formspec_version[4]",
        "size[11.75,10.425]",
        "label[0.375,0.375;" .. F(C(mcl_formspec.label_color, S("Bucket Sieve"))) .. "]",

        mcl_formspec.get_itemslot_bg_v4(2.875, 2, 1, 1),
        "list[context;src;2.875,2;1,1;]",

        "image[5.125,2;1.5,1;gui_furnace_arrow_bg.png^[lowpart:" .. percent_complete ..
            ":gui_furnace_arrow_fg.png^[transformR270]",

        mcl_formspec.get_itemslot_bg_v4(7.875, 1.375, 2, 2),
        "list[context;dst;7.875,1.375;2,2;]",

        "label[0.375,4.7;" .. F(C(mcl_formspec.label_color, S("Inventory"))) .. "]",
        mcl_formspec.get_itemslot_bg_v4(0.375, 5.1, 9, 3),
        "list[current_player;main;0.375,5.1;9,3;9]",

        mcl_formspec.get_itemslot_bg_v4(0.375, 9.05, 9, 1),
        "list[current_player;main;0.375,9.05;9,1;]",

        "listring[context;dst]",
        "listring[current_player;main]",
        "listring[context;src]",
        "listring[current_player;main]",
    })
end

-- ---------------------
-- Callbacks and helpers
-- ---------------------

local function run_bucket_sieve_effects(pos)
    core.sound_play("mcl_sounds_dug_water", { pos = pos, gain = 0.5, max_hear_distance = 8 }, true)
    core.add_particlespawner({ time = 0.5, amount = 8, collisiondetection = false, collision_removal = false,
        pos = { min = vector.new(pos.x - 0.375, pos.y + 0.375, pos.z - 0.375), max = vector.new(pos.x + 0.375, pos.y, pos.z + 0.375) },
        vel = { min = vector.new(-1, 2, -1), max = vector.new(1, 4, 1) },
        acc = { min = vector.new(0, -9.81, 0), max = vector.new(0, -9.81, 0) },
        exptime = { min = 0.3, max = 0.6}, size = { min = 0.5, max = 1 },
        texture = { name = "default_water_source_animated.png" }
    })
end

local function bucket_sieve_on_punch(pos, node, puncher, pointed_thing)
    if puncher:is_player() then
        local meta = core.get_meta(pos)
        if puncher:get_wielded_item():is_empty() then return end
        local wielded_item_name = puncher:get_wielded_item():get_name()
        if sieve_liquid_container[wielded_item_name] then
            local inv = meta:get_inventory()
            if inv:is_empty("src") then return end
            local def = core.registered_nodes[node.name]
            local input = inv:get_stack("src", 1):get_name()
            if not room_for_items(inv, "dst", recipes_by_input[def._mcl_sieve_type][input].products) then
                meta:set_string("infotext", S("Bucket sieve output full, make some space by removing products."))
                return
            end
            local num_punches = meta:get_int("num_punches") + 1
            local pct = 100 * num_punches / PUNCHES_TO_SIEVE
            meta:set_string("infotext", S("Bucket sieving completed: ") .. math.round(pct) .. "%")
            meta:set_string("formspec", bucket_sieve_formspec(pct))
            run_bucket_sieve_effects(pos)
            if num_punches < PUNCHES_TO_SIEVE then
                meta:set_int("num_punches", num_punches)
            else
                meta:set_int("num_punches", 0)
                puncher:set_wielded_item(sieve_liquid_container[wielded_item_name].empty, true)
                local ore = get_random_ore(def._mcl_sieve_type, input)
                inv:remove_item("src", input)
                inv:add_item("dst", recipes_by_input[def._mcl_sieve_type][input].leftover)
                if ore then inv:add_item("dst", ore) end
                if inv:is_empty("src") then
                    meta:set_string("infotext", S("Bucket sieve input empty, put material and punch with water container."))
                else
                    meta:set_string("infotext", S("Bucket sieve ready."))
                end
                meta:set_string("formspec", bucket_sieve_formspec(0))
            end
            local new_name = sieve_node_name[def._mcl_sieve_type][num_punches % sieve_node_cycles[def._mcl_sieve_type]]
            if new_name ~= node.name then
                node.name = new_name
                core.swap_node(pos, node)
            end
            return
        end
    end
    core.node_punch(pos, node, puncher, pointed_thing)
end

local function bucket_sieve_allow_put(pos, listname, index, stack, player)
    local playername = player:get_player_name()
    if core.is_protected(pos, playername) then
        core.record_protection_violation(pos, playername)
        return 0
    end
    local node = core.get_node_or_nil(pos)
    if not node then return 0 end
    local def = core.registered_nodes[node.name]
    if listname == "src" and allowed_inputs[def._mcl_sieve_type][stack:get_name()] then
        return stack:get_count()
    end
    return 0
end

local function bucket_sieve_on_put(pos, listname, index, stack, player)
    local meta = core.get_meta(pos)
    local inv = meta:get_inventory()
    if listname == "src" and not inv:is_empty("src") then
        local num_punches = meta:get_int("num_punches")
        local pct = 100 * num_punches / PUNCHES_TO_SIEVE
        meta:set_string("infotext", S("Bucket sieving completed: ") .. math.round(pct) .. "%")
        meta:set_string("formspec", bucket_sieve_formspec(pct))
    end
end

local function bucket_sieve_on_take(pos, listname, index, stack, player)
    local node = core.get_node_or_nil(pos)
    if not node then return end
    local def = core.registered_nodes[node.name]
    local meta = core.get_meta(pos)
    local inv = meta:get_inventory()
    if listname == "src" and inv:is_empty("src") then
        meta:set_int("num_punches", 0)
        meta:set_string("infotext", S("Bucket sieve input empty, put material and punch with water container."))
        meta:set_string("formspec", bucket_sieve_formspec(0))
        core.swap_node(pos, { name = sieve_node_name[def._mcl_sieve_type][0] })
    end
end

-- ----
-- Help
-- ----

local function bucket_sieve_doc_items_usagehelp()
    local c = {}
    for i, _ in pairs(sieve_liquid_container) do
       table.insert(c, core.get_translated_string("", core.registered_items[i].description))
    end
    local p = {}
    for _, r in ipairs(sieve_recipe[SIEVE_TYPE_BUCKET]) do
        table.insert(p, " * " .. S("Input:") .. " " .. core.get_translated_string("", core.registered_nodes[r.input].description) .. " ; ")
        table.insert(p, S("Leftover:") .. " " .. core.get_translated_string("", core.registered_nodes[r.leftover].description) .. " ; ")
        local y = {}
        for o, q in pairs(r.outputs) do
            table.insert(y, q .. "/" .. r.samples .. " " .. core.get_translated_string("", core.registered_items[o].description))
        end
        table.insert(p, S("Yield chances:") .. " " .. table.concat(y, " , ") .. "\n")
    end
    return table.concat({
        S("This kind of sieve requires manual operation."), "\n",
        S("Use the sieve to open the sieve menu."), " ",
        S("Put material in source slot and punch machine with full water container."), "\n",
        S("Sieving always produces one leftover material."), " ",
        S("Additionally, there is a chance that valuable ore is gained in the process."), "\n",
        S("It takes"), " ", PUNCHES_TO_SIEVE, " ",
        S("punches to sieve source material and uses all water in container, so having a water source nearby is recommended."), "\n\n",
        S("Water containers that can be used:"), " ", table.concat(c, " , "), "\n\n",
        S("Process ingredients and products:"), "\n", table.concat(p),
    })
end

-- -----
-- Nodes
-- -----

core.register_node("mcl_sieving:bucket_sieve",
{
    description = S("Bucket Sieve"),
    paramtype2 = "facedir",
    is_ground_content = false,
    drawtype = "nodebox",
    tiles = {
        "bucket_sieve_top.png",
        "bucket_sieve_bottom.png",
        "bucket_sieve_side.png",
        "bucket_sieve_side.png",
        "bucket_sieve_side.png",
        "bucket_sieve_side.png",
    },
    -- Can also be used for collision_box
    selection_box = {
        type = "fixed",
        fixed = {{-16/32, -16/32, -16/32, 16/32, 16/32, 16/32}},
    },
    node_box = {
        type = "fixed",
        fixed = {
            {-16/32, 0, -16/32, 16/32, 16/32, -12/32},
            {-16/32, -16/32, -12/32, -12/32, 16/32, -8/32},
            {-16/32, 0, -8/32, -12/32, 16/32, 16/32},
            {-16/32, -16/32, -16/32, -8/32, 0, -12/32},
            {-16/32, -16/32, 8/32, -12/32, 0, 16/32},
            {-12/32, 0, 12/32, 16/32, 16/32, 16/32},
            {-12/32, -16/32, 12/32, -8/32, 0, 16/32},
            {8/32, -16/32, -16/32, 16/32, 0, -12/32},
            {8/32, -16/32, 12/32, 16/32, 0, 16/32},
            {12/32, -16/32, -12/32, 16/32, 16/32, -8/32},
            {12/32, 0, -8/32, 16/32, 16/32, 12/32},
            {12/32, -16/32, 8/32, 16/32, 0, 12/32},
            {-12/32, 4/32, -12/32, 12/32, 12/32, 12/32},
            {-12/32, 12/32, 4/32, 12/32, 16/32, 8/32},
        },
    },
    sounds = mcl_sounds.node_sound_defaults(),
    groups = {
        pickaxey = 2,
        deco_block = 1,
        oddly_breakable_by_hand = 0,
        unmovable_by_piston = 1
    },
    on_punch = bucket_sieve_on_punch,
    on_construct = function(pos)
        local meta = core.get_meta(pos)
        local inv = meta:get_inventory()
        inv:set_size('src', 1)
        inv:set_size('dst', 4)
        meta:set_int("num_punches", 0)
        meta:set_string("infotext", S("Bucket sieve ready, put material and punch with water container."))
        meta:set_string("formspec", bucket_sieve_formspec(0))
    end,
    allow_metadata_inventory_put = bucket_sieve_allow_put,
    allow_metadata_inventory_move = function(...) return 0 end,
    allow_metadata_inventory_take = check_inventory_take_protection,
    on_metadata_inventory_put = bucket_sieve_on_put,
    on_metadata_inventory_take = bucket_sieve_on_take,
    after_dig_node = mcl_util.drop_items_from_meta_container({ "src", "dst" }),
    -- documentation
    _doc_items_longdesc = S("Bucket Sieve allows to extract valuable ores from various ground materials."),
    _doc_items_usagehelp = bucket_sieve_doc_items_usagehelp(),
    -- mineclonia
    _mcl_hardness = 2.5,
    -- custom fields
    _mcl_sieve_type = SIEVE_TYPE_BUCKET
})

core.register_node("mcl_sieving:bucket_sieve_2",
{
    description = S("Bucket Sieve"),
    paramtype2 = "facedir",
    drop = "mcl_sieving:bucket_sieve",
    is_ground_content = false,
    drawtype = "nodebox",
    tiles = {
        "bucket_sieve_top_2.png",
        "bucket_sieve_bottom.png",
        "bucket_sieve_side.png",
        "bucket_sieve_side.png",
        "bucket_sieve_side.png",
        "bucket_sieve_side.png",
    },
    -- Can also be used for collision_box
    selection_box = {
        type = "fixed",
        fixed = {{-16/32, -16/32, -16/32, 16/32, 16/32, 16/32}},
    },
    node_box = {
        type = "fixed",
        fixed = {
            {-16/32, 0, -16/32, 16/32, 16/32, -12/32},
            {-16/32, -16/32, -12/32, -12/32, 16/32, -8/32},
            {-16/32, 0, -8/32, -12/32, 16/32, 16/32},
            {-16/32, -16/32, -16/32, -8/32, 0, -12/32},
            {-16/32, -16/32, 8/32, -12/32, 0, 16/32},
            {-12/32, 0, 12/32, 16/32, 16/32, 16/32},
            {-12/32, -16/32, 12/32, -8/32, 0, 16/32},
            {8/32, -16/32, -16/32, 16/32, 0, -12/32},
            {8/32, -16/32, 12/32, 16/32, 0, 16/32},
            {12/32, -16/32, -12/32, 16/32, 16/32, -8/32},
            {12/32, 0, -8/32, 16/32, 16/32, 12/32},
            {12/32, -16/32, 8/32, 16/32, 0, 12/32},
            {-12/32, 4/32, -12/32, 12/32, 12/32, 12/32},
            {-12/32, 12/32, -8/32, 12/32, 16/32, -4/32},
        },
    },
    sounds = mcl_sounds.node_sound_defaults(),
    groups = {
        pickaxey = 2,
        deco_block = 1,
        oddly_breakable_by_hand = 0,
        unmovable_by_piston = 1,
        not_in_creative_inventory = 1,
        _doc_hidden = 1
    },
    on_punch = bucket_sieve_on_punch,
    allow_metadata_inventory_put = bucket_sieve_allow_put,
    allow_metadata_inventory_move = function(...) return 0 end,
    allow_metadata_inventory_take = check_inventory_take_protection,
    on_metadata_inventory_put = bucket_sieve_on_put,
    on_metadata_inventory_take = bucket_sieve_on_take,
    after_dig_node = mcl_util.drop_items_from_meta_container({ "src", "dst" }),
    -- mineclonia
    _mcl_hardness = 2.5,
    -- custom fields
    _mcl_sieve_type = SIEVE_TYPE_BUCKET
})

-- ========
-- Crafting
-- ========

core.register_craft({
    output = "mcl_sieving:bucket_sieve",
    recipe = {
        { "mcl_core:iron_ingot", "mcl_core:stick",      "mcl_core:iron_ingot" },
        { "group:wood",          "mcl_core:iron_ingot", "group:wood"          },
        { "group:wood",          "mcl_chests:chest",    "group:wood"          },
    }
})

-- vi: tabstop=4 shiftwidth=4 expandtab
