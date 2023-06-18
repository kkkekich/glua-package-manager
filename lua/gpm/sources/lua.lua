local gpm = gpm

-- Libraries
local package = gpm.package
local promise = promise
local paths = gpm.paths
local string = string
local table = table
local fs = gpm.fs

-- Variables
local MENU_DLL = MENU_DLL
local SERVER = SERVER
local ipairs = ipairs

if efsw ~= nil then

    local logger = gpm.Logger
    local function catch( message )
        logger:Error( message )
    end

    hook.Add( "FileWatchEvent", "GPM.Sources.Lua.Hot-Reload", function( action, _, filePath )
        if action <= 0 then return end

        local importPath = string.match( string.sub( filePath, 5 ), "packages/[^/]+" )
        if not importPath then return end

        local pkg = gpm.Packages[ importPath ]
        if not pkg then return end

        if not pkg:IsInstalled() then return end
        if pkg:IsReloading() then return end
        pkg:Reload():Catch( catch )
    end )

end

module( "gpm.sources.lua" )

function CanImport( filePath )
    if fs.IsDir( filePath, "LUA" ) then return true end
    if fs.IsFile( filePath, "LUA" ) then
        local extension = string.GetExtensionFromFilename( filePath )
        return extension == "moon" or extension == "lua"
    end

    return false
end

GetMetadata = promise.Async( function( importPath )
    importPath = paths.Fix( importPath )
    local metadata = {}

    if fs.IsDir( importPath, "LUA" ) then
        if SERVER or MENU_DLL then
            gpm.PreCacheMoon( importPath, true )
        end

        local packagePath = importPath .. "/package.lua"
        if fs.IsFile( packagePath, "LUA" ) then
            local ok, result = gpm.CompileLua( packagePath ):SafeAwait()
            if not ok then
                return promise.Reject( result )
            end

            table.Merge( metadata, package.ExtractMetadata( result ) )
            metadata.packagepath = packagePath
        else
            metadata.autorun = true
        end

        if SERVER or MENU_DLL then
            fs.Watch( importPath .. "/", "lsv" )
        end
    elseif fs.IsFile( importPath, "LUA" ) then
        metadata.autorun = true

        if ( SERVER or MENU_DLL ) and string.GetExtensionFromFilename( importPath ) == "moon" then
            gpm.PreCacheMoon( importPath, false )
        end

        importPath = paths.FormatToLua( importPath )
        metadata.init = importPath

        if SERVER or MENU_DLL then
            fs.Watch( importPath, "lsv" )
        end
    end

    return metadata
end )

if SERVER then

    local addCSLuaFile = package.AddCSLuaFile
    function SendToClient( metadata )
        local packagePath = metadata.packagepath
        if packagePath then
            addCSLuaFile( packagePath )
        end

        local importPath = metadata.importpath
        local isInFolder = fs.IsDir( importPath, "lsv" )

        local client = metadata.init.client
        if client then
            local filePath = importPath .. "/" .. client
            if fs.IsFile( filePath, "lsv" ) then
                addCSLuaFile( filePath )
            elseif fs.IsFile( client, "lsv" ) then
                addCSLuaFile( client )
            end
        end

        local send = metadata.send
        if send then
            for _, filePath in ipairs( send ) do
                if isInFolder then
                    local localFilePath = importPath .. "/" .. filePath
                    if fs.IsFile( localFilePath, "lsv" ) then
                        addCSLuaFile( localFilePath )
                        continue
                    end
                end

                if fs.IsFile( filePath, "lsv" ) then
                    addCSLuaFile( filePath )
                end
            end
        end
    end

end

CompileMain = promise.Async( function( metadata )
    local filePath = package.GetCurrentInitByRealm( metadata.init )
    if not fs.IsFile( filePath, "LUA" ) then
        filePath = metadata.importpath .. "/" .. filePath
        if not fs.IsFile( filePath, "LUA" ) then
            return promise.Reject( "Package init file '" .. filePath .. "' is missing." )
        end
    end

    return gpm.Compile( filePath )
end )

Import = promise.Async( function( metadata )
    local ok, result = CompileMain( metadata ):SafeAwait()
    if not ok then
        return promise.Reject( result )
    end

    return package.Initialize( metadata, result )
end )

Reload = promise.Async( function( pkg, metadata )
    table.Empty( pkg.Files )

    if SERVER then
        SendToClient( metadata )
    end

    local ok, result = CompileMain( metadata ):SafeAwait()
    if not ok then
        return promise.Reject( result )
    end

    pkg.Init = result

    local ok, result = pkg:Initialize( metadata ):SafeAwait()
    if not ok then
        return promise.Reject( result )
    end

    local ok, result = pkg:Run():SafeAwait()
    if not ok then
        return promise.Reject( result )
    end

    return result
end )