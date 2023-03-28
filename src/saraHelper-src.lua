---@class config
local config = {
    --- World list that has fire inside them use : to specify door id, example: world:doorid.
    worlds = {
        'world1',
        'world2:doorid'
    },

    --- Optional to use if you want to take fire hose from another world.
    storage = 'storage:doorid',

    --- Optional to use door id if you don't specify the door id manually per worlds.
    id = '',

    --- Webhook URL to send the information of any activities.
    webhook = ''
}

---@alias WorldStatus
---| '"SCANNING"' # Scanning process
---| '"NO_FIRE"' # No fire detected
---| '"DETECTED_FIRE"' # Fire detected
---| '"TAKING_ITEM"' # Taking item
---| '"NO_ITEM"' # Taking item
---| '"CLEARING"' # Clearing fire
---| '"STORING_ITEM"' # Storing item
---| '"FINISHED"' # Finished

---@alias HandleItemCommand
---| '"TAKE"' # Take item
---| '"STORE"' # Store item

---@class TileCache
---@field public x number
---@field public y number

---@class WorldCache
---@field public STATUS WorldStatus
---@field public TILES TileCache[]
---@field public WORLD string

---@class saraHelper
local saraHelper = { _VERSION = '1.0', _AUTHOR = 'junssekut#4964', _CONTRIBUTORS = {} }

local saraCore = assert(load(request('GET', 'https://raw.githubusercontent.com/junssekut/saraCore/main/src/saraCore.lua'))())

local tinsert = table.insert
local sformat = string.format
local mfloor = math.floor

local rawerror = _G.error

local error = function (message) rawerror(message, 0) end

local getBot = _G.getBot
local getTile = _G.getTile
local getObjects = _G.getObjects
local findPath = _G.findPath
local findClothes = _G.findClothes
local findItem = _G.findItem
local sleep = _G.sleep
local wear = _G.wear
local collect = _G.collect
local punch = _G.punch
local webhook = _G.webhook

local warp = saraCore.WorldHandler.warp --[[@as function]]
local winside = saraCore.WorldHandler.isInside --[[@as function]]
local tassertv = saraCore.AssertUtils.tassertv --[[@as function]]
local ldate = saraCore.Date --[[@as function]]
local check_connection = saraCore.Auth.c --[[@as function]]
local pcollect = saraCore.PacketHandler.collect --[[@as function]]
local drop = saraCore.InventoryHandler.drop --[[@as function]]
local getx = saraCore.TileHandler.getx --[[@as function]]
local nformat = saraCore.NumberUtils.nformat --[[@as function]]
local jencode = saraCore.Json.encode --[[@as function]]
local isprites = saraCore.ItemSprites --[[@as table]]

local FIRE_HOSE = 3066

---@type TileCache
local cache_take_position

---
---Tile position calculator for fire.
---
---@param x number
---@param y number
---@return number|nil, number|nil, number|nil, number|nil
---@nodiscard
local function calculateTile(x, y)
    tassertv('calculateTile<x>', x, 'number')
    tassertv('calculateTile<y>', y, 'number')

    if getTile(x, y).flags == 0 then
        sleep(100)

        return x, y, 0, 0
    end

    if getTile(x, y - 1).flags == 0 then
        if not findPath(x, y - 1) then
            sleep(500)
        else
            sleep(100)

            return x, y, 0, 1
        end
    end

    for i = -3, 3 do
        if x + i >= 0 and x + i <= 99 then
            local tile = getTile(x + i, y)

            if tile and tile.flags == 0 then
                if not findPath(x + i, y) then
                    sleep(500)
                else
                    sleep(100)

                    return x, y, -i, 0
                end
            end
        end
    end

    for i = -3, 3 do
        for j = -3, 3 do
            if (x + i >= 0 and x + i <= 99) and (y + j >= 0 and y + j <= 53) then
                local tile = getTile(x + i, y + j)

                if tile and tile.flags == 0 then
					if not findPath(x + i, y + j) then
						sleep(500)
					else
						sleep(100)

						return x, y, -i, -j
					end
				end
            end
        end
    end

    return nil
end

---
---Handle a tile that is on fire.
---
---@param cworld string
---@param cid string
---@param x number
---@param y number
local function handleTile(cworld, cid, x, y)
    tassertv('handleTile<x>', x, 'number')
    tassertv('handleTile<y>', y, 'number')

    local tile_x, tile_y, punch_x, punch_y = calculateTile(x, y)

    if not tile_x or not tile_y or not punch_x or not punch_y then return end

    local fail_safe = 0

    while true do
        check_connection(cworld, cid, tile_x, tile_y, true)

        punch(punch_x, punch_y)

        local bot = getBot()
        local pos_x, pos_y = bot.x, bot.y

        sendPacketRaw({
            type = 0,
            flags = 2592,
            pos_x = pos_x,
            pos_y = pos_y,
            int_x = mfloor(pos_x * ( 1 / 32 )) + punch_x,
            int_y = mfloor(pos_y * ( 1 / 32 )) + punch_y
        })

        local tile = getTile(tile_x, tile_y)

        if (tile and tile.extra ~= 16) or fail_safe >= 0 then sleep(150); break end

        fail_safe = fail_safe + 1

        sleep(150)
    end

end

---
---Handle auto equip and storing items.
---
---@param command HandleItemCommand
---@param cworld string
---@param cid string
---@param item_id number
---@return boolean
local function handleItem(command, cworld, cid, item_id)
    local sworld, sid = config.storage:match('(.+):(.+)')

    while not warp(sworld, sid) do
        sleep(5000)
    end

    sleep(2500)

    if command == 'TAKE' then
        for _, object in pairs(getObjects()) do
            if findItem(object.id) ~= 0 then break end

            if object.id == item_id then
                local object_x, object_y = mfloor(object.x * ( 1 / 32 )), mfloor(object.y * ( 1 / 32 ))

                if not findPath(object_x + 1, object_y) then
                    sleep(500)
                else
                    sleep(200)

                    check_connection(sworld, sid, object_x + 1, object_y, true)

                    cache_take_position = { x = object_x, y = object_y }

                    pcollect(object.oid, object.x, object.y)

                    sleep(200)

                    if findItem(object.id) ~= 0 then break end
                end
            end
        end

        if findItem(item_id) == 0 then collect(3) end

        if findItem(item_id) > 1 then drop(item_id, findItem(item_id) - 1) end

        if findItem(item_id) == 0 then
            return false
        end

        while not findClothes(item_id) do
            check_connection()

            wear(item_id)

            sleep(200)
        end

        while not warp(cworld, cid) do
            sleep(5000)
        end

        sleep(2500)
    end

    if command == 'STORE' then
        if not cache_take_position then
            local bot = getBot()

            cache_take_position = { x = mfloor(bot.x * ( 1 / 32 )) - 1, y = mfloor(bot.y * ( 1 / 32 )) }
        end

        while findItem(item_id) ~= 0 do
            check_connection()

            if not findPath(cache_take_position.x + 1, cache_take_position.y) then
                sleep(500)
            else
                sleep(200)

                check_connection(sworld, sid, cache_take_position.x + 1, cache_take_position.y, true)

                drop(item_id)

                if findItem(item_id) == 0 then break end
            end

            sleep(1000)
        end
    end

    sleep(1000)

    return command == 'TAKE' and (findClothes(item_id)) or (findItem(item_id) == 0)
end

---
---Execute world data and begin to clear the fires.
---
---@param world_data string
---@param last boolean
---@return WorldCache
---@nodiscard
local function execute(world_data, last)
    tassertv('execute<world>', world_data, 'string')

    local world, id = world_data, ''

    if world:find(':') then world, id = world:match('(.+):(.+)') else id = config.id end

    world = world:upper()

    ---@class WorldCache
    local caches = {
        WORLD = world,
        ---@type TileCache[]
        TILES = {}
    }

    local caches_meta

    do
        local protected_caches = {}
        caches_meta = {
            __index = function (table_value, key)
                return protected_caches[key]
            end,

            __newindex = function (table_value, key, value)
                if key == 'STATUS' then
                    local bot = getBot()

                    webhook({ url = config.webhook, username = 'saraHelper', content = sformat('[**%s**] %s: %s', bot.world, bot.name, value)})

                    sleep(250)
                end

                protected_caches[key] = value
            end
        }
    end

    setmetatable(caches, caches_meta)

    check_connection()

    if winside(world) then
        warp('exit')
        sleep(2500)
    end

    while not warp(world, id) do
        sleep(5000)
    end

    ---@type WorldStatus
    caches.STATUS = "SCANNING"

    sleep(2500)

    for y = 0, 53 do
        for x = 0, 99 do
            if getTile(x, y).extra == 16 then
                if caches.STATUS ~= 'DETECTED_FIRE' then caches.STATUS = "DETECTED_FIRE" end

                tinsert(caches.TILES, { x = x, y = y })
            end
        end
    end

    if #caches.TILES == 0 then
        caches.STATUS = "NO_FIRE"
        return caches
    end

    if findItem(FIRE_HOSE) == 0 then
        caches.STATUS = "TAKING_ITEM"

        if not handleItem('TAKE', world, id, FIRE_HOSE) then
            caches.STATUS = 'NO_ITEM'
            return caches
        end

    end

    caches.STATUS = "CLEARING"

    while true do
        local fire_exist = false

        while not warp(world, id) do
            sleep(5000)
        end

        sleep(2500)

        for y = 0, 53 do
            for x = 0, 99 do

                if getTile(x, y).extra == 16 then
                    fire_exist = true

                    handleTile(world, id, x, y)
                end

            end
        end

        if not fire_exist then break end

        sleep(5000)

        while not warp('exit') do
            sleep(5000)
        end

        sleep(5000)
    end

    if last then
        caches.STATUS = "STORING_ITEM"

        handleItem('STORE', world, id, FIRE_HOSE)
    end

    caches.STATUS = "FINISHED"

    return caches
end

---
---Initialize and run the script.
---
---@param config_value config
function saraHelper.init(config_value)
    tassertv('saraHelper:init<config_value>', config_value, 'table')

    config = config_value

    ---@type WorldCache[]
    local result_caches = {}

    for i = 1, #config.worlds do
        local world_data = config.worlds[i]

        local executed, cache = pcall(execute, world_data, i == #config.worlds)

        if executed then
            tinsert(result_caches, cache)
        else
            local error_logs = io.open('error_logs.txt', 'a')
            if error_logs then error_logs:write(sformat('[ERROR][%s]: %s\n', ldate():fmt('%X'), 'At world `' .. world_data .. '` ( index ' .. i .. ' ) ' .. cache)); error_logs:close() end
        end
    end

    if #config.worlds ~= #result_caches then error('An error occured, please see error_logs.txt') end

    local fields = {
        { name = 'World Name', value = '', inline = true },
        { name = 'Fire Detected', value = '', inline = true },
        { name = 'Status', value = '', inline = true }
    }

    for i = 1, #result_caches do
        local cache = result_caches[i]

        fields[1].value = fields[1].value .. isprites.GLOBE .. ' ' .. cache.WORLD .. '\n'
        fields[2].value = fields[2].value .. isprites.FIRE_WAND .. ' x' .. nformat(#cache.TILES) .. ' Fires' .. '\n'
        fields[3].value = fields[3].value .. (cache.STATUS == "FINISHED" and isprites.GROWTOPIA_YES or isprites.GROWTOPIA_NO) .. ' ' .. cache.STATUS .. '\n'
    end

    webhook({
        url = config.webhook,
        username = 'saraHelper',
        avatar = '',
        embed = jencode({
            title = sformat('HELPER SUMMARY'),
            color = 0,
            fields = fields,
            footer = saraCore.WebhookHandler.getDefaultFooter(),
            timestamp = ldate(true):fmt('${iso}')
        }) --[[@as string]]
    })
end

return saraHelper