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

--- Fetch the online script and load it.
local saraHelper = assert(load(request('GET', 'https://raw.githubusercontent.com/junssekut/saraHelper/main/src/saraHelper-src.lua'))())

--- Initialize with your custom config!
local status, message = pcall(saraHelper.init, config)

if not status then error('An error occured, please see error_logs.txt\n' .. message) end