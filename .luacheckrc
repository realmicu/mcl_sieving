unused_args = false
allow_defined_top = true
max_line_length = 240

ignore = {
    "131", -- Unused global variable
    "431", -- Shadowing an upvalue
    "432", -- Shadowing an upvalue argument
}

globals = {
    "mcl_sieving"
}

read_globals = {
    "core",
    "ItemStack",
    "INIT",
    "PLATFORM",
    "DIR_DELIM",
    "dump", "dump2",
    "fgettext", "fgettext_ne",
    "vector",
    "vector2",
    "VoxelArea", "VoxelManip",
    "PseudoRandom", "PcgRandom",
    "profiler",
    "Settings",
    "ValueNoise", "ValueNoiseMap",
    "tracy",
    "unpack",
    "doc",
    "mcl_sounds",
    "mcl_core",
    "mcl_formspec",
    "mcl_util",

    string = {fields = {"split", "trim"}},
    table  = {fields = {"copy", "copy_with_metatables", "getn", "indexof", "keyof", "insert_all", "shuffle", "update", "merge"}},
    math   = {fields = {"hypot", "round", "isfinite", "sign"}},
}
