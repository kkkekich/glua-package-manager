-- if not reqwest and util.IsBinaryModuleInstalled( "reqwest" ) then require( "reqwest" ) end
-- if not reqwest and not CHTTP and util.IsBinaryModuleInstalled( "chttp" ) then require( "chttp" ) end
-- local client = reqwest or CHTTP or HTTP

local client = HTTP
local promise = gpm.promise

module( "gpm.http" )

DEFAULT_TIMEOUT = 60

function HTTP( parameters )
    local p = promise.New()

    parameters.success = function( code, body, headers )
        p:Resolve( {
            ["code"] = code,
            ["body"] = body,
            ["headers"] = headers
        } )
    end

    parameters.failed = function( err )
        p:Reject( err )
    end

    local ok = client( parameters )
    if not ok then
        p:Reject( "failed to make http request" )
    end

    return p
end

function Fetch( url, headers, timeout )
    return HTTP( {
        ["url"] = url,
        ["headers"] = headers,
        ["timeout"] = timeout or DEFAULT_TIMEOUT
    } )
end

function Post( url, parameters, headers, timeout )
    return HTTP( {
        ["url"] = url,
        ["method"] = "POST",
        ["headers"] = headers,
        ["parameters"] = parameters,
        ["timeout"] = timeout or DEFAULT_TIMEOUT
    } )
end