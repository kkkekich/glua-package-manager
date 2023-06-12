-- Libraries
local asyncio = asyncio
local promise = promise
local string = string
local table = table
local util = util
local file = file
local efsw = efsw
local gpm = gpm

-- Variables
local CompileMoonString = CompileMoonString
local CompileString = CompileString
local debug_fempty = debug.fempty
local math_max = math.max
local logger = gpm.Logger
local SERVER = SERVER
local ipairs = ipairs
local assert = assert
local type = type

-- https://github.com/Pika-Software/gm_asyncio
-- https://github.com/WilliamVenner/gm_async_write
if util.IsBinaryModuleInstalled( "asyncio" ) and pcall( require, "asyncio" ) then
    logger:Info( "A third-party file system API 'asyncio' has been initialized." )
elseif SERVER and util.IsBinaryModuleInstalled( "async_write" ) and pcall( require, "async_write" ) then
    logger:Info( "A third-party file system API 'async_write' has been initialized." )
end

-- https://github.com/Pika-Software/gm_efsw
if util.IsBinaryModuleInstalled( "efsw" ) and pcall( require, "efsw" ) then
    logger:Info( "gm_efsw is initialized, package auto-reload are available." )
end

if efsw ~= nil then
    hook.Add( "FileWatchEvent", "GPM.AutoReload", function( actionID, _, filePath )
        local importPath = string.match( filePath, ".*/lua/(packages/.*)/" )
        if not importPath then return end

        local pkg = gpm.Packages[ importPath ]
        if pkg and pkg:IsInstalled() then
            gpm.Reload( importPath )
        end
    end )
end

module( "gpm.fs" )

Delete = file.Delete
Rename = file.Rename
Open = file.Open
Find = file.Find
Size = file.Size
Time = file.Time

function Exists( filePath, gamePath )
    if SERVER then return file.Exists( filePath, gamePath ) end
    if file.Exists( filePath, gamePath ) then return true end

    local files, folders = file.Find( filePath .. "*", gamePath )
    if not files or not folders then return false end
    if #files == 0 and #folders == 0 then return false end

    local splits = string.Split( filePath, "/" )
    local fileName = splits[ #splits ]

    return table.HasIValue( files, fileName ) or table.HasIValue( folders, fileName )
end

function IsDir( filePath, gamePath )
    if SERVER then return file.IsDir( filePath, gamePath ) end
    if file.IsDir( filePath, gamePath ) then return true end

    local _, folders = file.Find( filePath .. "*", gamePath )
    if folders == nil or #folders == 0 then return false end

    local splits = string.Split( filePath, "/" )
    return table.HasIValue( folders, splits[ #splits ] )
end

function IsFile( filePath, gamePath )
    if SERVER then return file.Exists( filePath, gamePath ) and not file.IsDir( filePath, gamePath ) end
    if file.Exists( filePath, gamePath ) and not file.IsDir( filePath, gamePath ) then return true end

    local files, _ = file.Find( filePath .. "*", gamePath )
    if not files or #files == 0 then return false end
    local splits = string.Split( filePath, "/" )

    return table.HasIValue( files, splits[ #splits ] )
end

function Read( filePath, gamePath, lenght )
    local fileClass = file.Open( filePath, "rb", gamePath )
    if not fileClass then return end

    local fileContent = fileClass:Read( type( lenght ) == "number" and math_max( 0, lenght ) or fileClass:Size() )
    fileClass:Close()

    return fileContent
end

function Write( filePath, contents )
    local fileClass = file.Open( filePath, "wb", "DATA" )
    if not fileClass then return end
    fileClass:Write( contents )
    fileClass:Close()
end

function Append( filePath, contents )
    local fileClass = file.Open( filePath, "ab", "DATA" )
    if not fileClass then return end
    fileClass:Write( contents )
    fileClass:Close()
end

function CreateDir( folderPath )
    local currentPath = nil

    for _, folderName in ipairs( string.Split( folderPath, "/" ) ) do
        if not folderName then continue end

        currentPath = currentPath and ( currentPath .. "/" .. folderName ) or folderName
        if IsDir( currentPath, "DATA" ) then continue end

        file.Delete( currentPath )
        file.CreateDir( currentPath )
    end

    return currentPath
end

CompileLua = promise.Async( function( filePath, gamePath, handleError )
    local ok, result = AsyncRead( filePath, gamePath ):SafeAwait()
    if not ok then
        return promise.Reject( result )
    end

    local func = CompileString( result.fileContent, result.filePath, handleError )
    assert( type( func ) == "function", "Lua file '" .. filePath .. "' (" .. gamePath .. ") compilation failed." )
    return func
end )

CompileMoon = promise.Async( function( filePath, gamePath, handleError )
    local ok, result = AsyncRead( filePath, gamePath ):SafeAwait()
    if not ok then
        return promise.Reject( result )
    end

    return CompileMoonString( result.fileContent, result.filePath, handleError )
end )

Watch = debug_fempty
UnWatch = debug_fempty

if efsw ~= nil then
    local watchList = efsw.WatchList
    if type( watchList ) ~= "table" then
        watchList = {}; efsw.WatchList = watchList
    end

    function Watch( filePath, gamePath )
        if watchList[ filePath .. ";" .. gamePath ] then return end
        watchList[ filePath .. ";" .. gamePath ] = efsw.Watch( filePath, gamePath )
    end

    function UnWatch( filePath, gamePath )
        local watchID = watchList[ filePath .. ";" .. gamePath ]
        if watchID then
            efsw.Unwatch( watchID )
            watchList[ filePath .. ";" .. gamePath ] = nil
        end
    end
end

if type( asyncio ) == "table" then
    function AsyncRead( filePath, gamePath )
        local p = promise.New()

        if asyncio.AsyncRead( filePath, gamePath, function( filePath, gamePath, status, fileContent )
            if status ~= 0 then
                return p:Reject( "Error code: " .. status )
            end

            p:Resolve( {
                ["fileContent"] = fileContent,
                ["filePath"] = filePath,
                ["gamePath"] = gamePath
            } )
        end ) ~= 0 then
            p:Reject( "Error code: " .. status )
        end

        return p
    end

    function AsyncWrite( filePath, fileContent )
        local p = promise.New()

        if asyncio.AsyncWrite( filePath, fileContent, function( filePath, gamePath, status )
            if status ~= 0 then
                return p:Reject( "Error code: " .. status )
            end

            p:Resolve( {
                ["filePath"] = filePath,
                ["gamePath"] = gamePath
            } )
        end ) ~= 0 then
            p:Reject( "Error code: " .. status )
        end

        return p
    end

    function AsyncAppend( filePath, fileContent )
        local p = promise.New()

        if asyncio.AsyncAppend( filePath, fileContent, function( filePath, gamePath, status )
            if status ~= 0 then
                return p:Reject( "Error code: " .. status )
            end

            p:Resolve( {
                ["filePath"] = filePath,
                ["gamePath"] = gamePath
            } )
        end ) ~= 0 then
            p:Reject( "Error code: " .. status )
        end

        return p
    end

    return
end

function AsyncRead( filePath, gamePath )
    local p = promise.New()

    if file.AsyncRead( filePath, gamePath, function( filePath, gamePath, status, fileContent )
        if status ~= 0 then
            return p:Reject( "Error code: " .. status )
        end

        p:Resolve( {
            ["filePath"] = filePath,
            ["gamePath"] = gamePath,
            ["fileContent"] = fileContent
        } )
    end ) ~= 0 then
        p:Reject( "Error code: " .. status )
    end

    return p
end

if type( file.AsyncWrite ) == "function" then

    function AsyncWrite( filePath, fileContent )
        local p = promise.New()

        if file.AsyncWrite( filePath, fileContent, function( filePath, status )
            if status ~= 0 then
                return p:Reject( "Error code: " .. status )
            end

            p:Resolve( {
                ["filePath"] = filePath
            } )
        end ) ~= 0 then
            p:Reject( "Error code: " .. status )
        end

        return p
    end

else

    function AsyncWrite( filePath, fileContent )
        local p = promise.New()

        Write( filePath, fileContent )

        if Exists( filePath, "DATA" ) then
            p:Resolve( {
                ["filePath"] = filePath
            } )
        else
            p:Reject( "failed" )
        end

        return p
    end

end

if type( file.AsyncAppen ) == "function" then

    function AsyncAppend( filePath, fileContent )
        local p = promise.New()

        if file.AsyncAppend( filePath, fileContent, function( filePath, status )
            if status ~= 0 then
                return p:Reject( "Error code: " .. status )
            end

            p:Resolve( {
                ["filePath"] = filePath
            } )
        end ) ~= 0 then
            p:Reject( "Error code: " .. status )
        end

        return p
    end

else

    function AsyncAppend( filePath, fileContent )
        local p = promise.New()

        Append( filePath, fileContent )
        p:Resolve( {
            ["filePath"] = filePath
        } )

        return p
    end

end