local next = next 
local tonumber = tonumber 
local bit_band = bit.band
--------------------------------------------------------------------------------
local BufferInterface = H3xLoad.Libs.BufferInterface

local Config = H3xLoad.Config

util.AddNetworkString( "H3xLoad_WorkshopAddons" )

function H3xLoad.NewCacheID()
    H3xLoad.CacheID = tostring(os.time())
    file.Write( "h3xload/cache_id.txt", H3xLoad.CacheID )
    SetGlobalString( "H3xLoad_CacheID", H3xLoad.CacheID )
    return H3xLoad.CacheID
end


function H3xLoad.GenerateResourceCache()
    H3xLoad.NewCacheID()

    local resources = resource.GetList()
    local cache_file = H3xLoad.CacheFileName()
    local res_count = #resources
    MsgN( "[H3xLoad] Total legacy resources: ", res_count )
    MsgN( "[H3xLoad] Generating resource cache..." )

    ------------------------
    -- Write GMA file
    local time_start = SysTime()
    local succ = H3xLoad.WriteGMA( cache_file, resources )
    local time_end = SysTime()

    if succ then
        MsgN( "[H3xLoad] Completed! (",time_end-time_start,"s)" )
    else
        return false
    end
    ------------------------
    -- Write cache information
    local fl = file.Open("h3xload/cache_info.dat", "wb", "DATA")
    if not fl then
        ErrorNoHalt("[H3xLoad] Unable to open h3xload/cache_info.dat")
        return false
    else
        local buffer = BufferInterface(fl)
        buffer:WriteString(H3xLoad.CacheID)

        -- Write config info
        buffer:WriteBool(Config.RuntimeLoadLegacy or false)
        buffer:WriteBool(Config.RuntimeLoadWorkshop or false)
        buffer:WriteUInt16(Config.FileNet_BlockSize or 0)
        buffer:WriteUInt16(Config.FileNet_BurstCount or 0)

        -- Write resource inof
        buffer:WriteUInt32(res_count)
        for i=1, res_count do
            local filename = resources[i]

            local fl_time = 0
            local fl_size = 0
            if file.Exists(filename, "GAME") then
                fl_time = file.Time( filename, "GAME" )
                fl_size = file.Size( filename, "GAME" )
            end

            buffer:WriteUInt8( #filename )
            buffer:WriteData( filename )
            buffer:WriteUInt32( fl_time )
            buffer:WriteUInt32( fl_size )
        end

        fl:Close()
    end

    ---------------------
    -- Compress
    MsgN("[H3xLoad] Compressing cache load...")
    local succ = H3xLoad.FileNet.Compress( cache_file, H3xLoad.CompressedCacheFileName() )
    if not succ then
        return false
    end

    return true
end

function H3xLoad.IsCacheValid()
    local resources = resource.GetList()
    local res_count = #resources

    if not file.Exists("h3xload/cache_info.dat", "DATA") then
        return false
    end

    if not file.Exists("h3xload/cache_id.dat", "DATA") then
        return false
    end

    local fl = file.Open("h3xload/cache_info.dat", "rb", "DATA")
    if not fl then
        ErrorNoHalt("[H3xLoad] Unable to open h3xload/cache_info.dat\n")
        return false
    else
        local buffer = BufferInterface(fl)
        if H3xLoad.GetCacheID() ~= buffer:ReadString() then fl:Close() return false end

        -- Compare config
        if (Config.RuntimeLoadLegacy or false) ~= buffer:ReadBool() then fl:Close() return false end
        if (Config.RuntimeLoadWorkshop or false) ~= buffer:ReadBool() then fl:Close() return false end
        if (Config.FileNet_BlockSize or 0) ~= buffer:ReadUInt16() then fl:Close() return false end
        if (Config.FileNet_BurstCount or 0) ~= buffer:ReadUInt16() then fl:Close() return false end

        -- Compare resources
        cache_res_count = buffer:ReadUInt32()
        if res_count ~= cache_res_count then
            fl:Close()
            return false
        end

        -- The order should usually stay the same, unless addon name is changed
        for i=1, res_count do
            local cache_filename_size = buffer:ReadUInt8()
            local cache_filename = buffer:ReadData( cache_filename_size )
            cache_fl_time = buffer:ReadUInt32()
            cache_fl_size = buffer:ReadUInt32()

            local filename = resources[i]
            local fl_time = 0
            local fl_size = 0
            if file.Exists(filename, "GAME") then
                fl_time = file.Time( filename, "GAME" )
                fl_size = file.Size( filename, "GAME" )
            end

            if filename ~= cache_filename or
                fl_time ~= cache_fl_time or
                fl_size ~= cache_fl_size
            then
                fl:Close()
                return false
            end
        end

        fl:Close()  
    end
    return true
end

function H3xLoad.SetupLegacyResources()
    if not Config.RuntimeLoadLegacy then return end

    if not H3xLoad.IsCacheValid() then
        MsgN( "[H3xLoad] Resource cache is not valid" )
        if H3xLoad.GenerateResourceCache() then
            H3xLoad.FileNet.OpenFile( H3xLoad.CompressedCacheFileName() )
        else
            MsgN( "[H3xLoad] Something went wrong while generating cache" )
            file.Delete( H3xLoad.CacheFileName() )
            file.Delete( H3xLoad.CompressedCacheFileName() )
            file.Delete( "h3xload/cache_info.dat" )
        end
    else
        MsgN( "[H3xLoad] Resource cache is up to date" )
        H3xLoad.GetCacheID() 
        H3xLoad.FileNet.OpenFile( H3xLoad.CompressedCacheFileName() )
    end
end

function H3xLoad.Initialize()
    MsgN( "[H3xLoad] Initializing..." )
    H3xLoad.SetupLegacyResources()
end


hook.Add("Initialize", "H3xLoad", function()
    -- Some badly coded scripts could add resources in Initialized hook
    timer.Simple(0, H3xLoad.Initialize)
end)

hook.Add("PlayerInitialSpawn", "H3xLoad", function(ply)
    if not Config.RuntimeLoadWorkshop then return end

    local workshop_addons = resource.GetWSList( )
    local num = #workshop_addons
    
    net.Start("H3xLoad_WorkshopAddons")
    net.WriteUInt( num, 16 )
    for i=1, num do
        net.WriteString( workshop_addons[i] )
    end
    net.Send(ply)
end)