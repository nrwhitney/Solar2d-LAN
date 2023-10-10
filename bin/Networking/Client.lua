local socket = require( "socket" )  -- Connection to socket library
--local JSON = require("json")

--local fallBackAddress = "8.8.8.8"

-- Check if this is socket 2 or later
local isSocket2 = (string.match( require("socket")._VERSION, "LuaSocket 2" ) ~= nil )
--print (isSocket2)

local forceIPV4 	= true
--local forceIPV4 	= false

local socketUDP 	= (isSocket2) and socket.udp or(socket.udp6 or socket.udp4 or socket.udp) 
local socketTCP 	= (isSocket2) and socket.tcp or(socket.tcp6 or socket.tcp4 or socket.tcp) 

if( forceIPV4 and isSocket2 == false ) then
	socketUDP 	= socket.udp4 or socket.udp 
	socketTCP 	= socket.tcp4 or socket.tcp
end

-- If we are using Socket 3, we still need to determine if the local network is
-- ipv4 or ipv6 compliant.  Assume it is, but test for failure
--local ipv6Test = true
--if( isSocket2 == false ) then
--	local socketTest1 = socket.udp6()
--	socketTest1:setpeername( "google.com", 54613 )
--	local testPeerIP = socketTest1:getsockname()
--	if (testPeerIP == "::") then
--		ipv6Test = false
--	end
--end

--print("ipv6Test:",ipv6Test)

--local peerIP, peerPort 
--local s = socketUDP()
--s:setpeername( "google.com", 54613 )
--peerIP, peerPort = s:getsockname(), 54613

--if( peerIP == nil ) then
--	s:setpeername( fallBackAddress, 54613 )
--	peerIP, peerPort = s:getsockname(), 54613
--end
--s = nil
--print("Network:", peerIP, peerPort, socketUDP, socketTCP )

local function connectToServer( ip, port )
    local tcp = socketTCP()
    tcp:connect( ip, port )
    if tcp == nil then
        return false
    end
    tcp:settimeout( 0 )
    tcp:setoption( "tcp-nodelay", true )  --disable Nagle's algorithm
    return tcp
end

local function Split(inputstr, sep)
    if inputstr ~= nil then
        if sep == nil then
                sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                table.insert(t, str)
        end
        if #t == 1 then
            return t[1]
        else
            return t
        end
    end
end

local function BuildFunction(Function, Args)
    local builder = Function.."|"
    if type(Args) == "table" then
        for i,v in pairs(Args) do
            builder = builder..v.."/"
        end
        builder = string.sub( builder, 1, string.len( builder ) - 1 )
        builder = builder.."\n"
    else
        builder = builder..Args.."\n"
    end
    return builder
end

local Client = {}

    ServerBroadcastFinder = nil
    FindSock = nil
    FoundServers = {}
    Client.StartFind = function( port )
        FoundServers = {}
        if ServerBroadcastFinder == nil then
            local connectionMessage = "g00pS3rv3r"

--            FindSock = socket.udp4()
            FindSock = socketUDP()
            FindSock:setsockname("*", port)
            FindSock:settimeout(0)

            local function look()
                repeat
                    local data, ip, port = FindSock:receivefrom()
                    if data then
                        local conMsg = string.sub(data, 1, 10)
                        local sName = string.sub(data, 11)
                        if conMsg == connectionMessage then
                            if not FoundServers[ip] then
                                FoundServers[ip] = {ip, sName}
                                if Client.onFound ~= nil then Client.onFound( ip, sName ) end
                            end
                        end
                    end
                until not data
             end
             ServerBroadcastFinder = timer.performWithDelay( 100, look, 0 )
         end
    end

    Client.StopFind = function()
        timer.cancel( ServerBroadcastFinder )
        ServerBroadcastFinder = nil
        FindSock:close()
        FindSock = nil
        return FoundServers
    end

    Client.StartClient = function( ip, port )

        local Ctrl = {}
        Ctrl.UID = ""
        Ctrl.IsHost = false
        Ctrl.ClientSock =  connectToServer( ip, port )
        Ctrl.SendBuffer = {}

        Ctrl.SendTo = function(UIDorUserName, Function, Args)
--            table.insert( Ctrl.SendBuffer, UID.."|"..BuildFunction(Function, Args) )
            table.insert( Ctrl.SendBuffer, UIDorUserName.."|"..BuildFunction(Function, Args) )
            
        end

        Ctrl.Send = function(Function, Args)
            table.insert( Ctrl.SendBuffer, ".|"..BuildFunction(Function, Args) )
        end

        Ctrl.StopClient = function()
            -- print("** STOPPING CLIENT **")
            Ctrl.SendBuffer = {}
            timer.cancel( Ctrl.clientPulse )
            Ctrl.clientPulse = nil
            if type(Ctrl.ClientSock) ~= "boolean" then
                Ctrl.ClientSock:close()
            end
            Ctrl.ClientSock = nil
        end

        local function cPulse()

            local allData = {}
            local data, err

            -- Receive
            repeat
                data, err = Ctrl.ClientSock:receive()
                if data then
                    table.insert( allData, data )
                end

                if ( err == "closed" and Ctrl.clientPulse ) then
                    Ctrl.ClientSock = connectToServer( ip, port )
                    -- print("type:", type(Ctrl.ClientSock))
                    if type(Ctrl.ClientSock) ~= "boolean" then
                        data, err = Ctrl.ClientSock:receive()
                        -- print("---", data, err, "---")
                        if err ~= "Socket is not connected" then
                            if data then
                                table.insert( allData, data )
                            end
                        else
                            if Ctrl.onDisconnect ~= nil then Ctrl.onDisconnect(err) end
                            Ctrl.StopClient()
                        end
                    end
                end
            until not data
     
            if ( #allData > 0 ) then
                for i, thisData in ipairs( allData ) do

                    local FunctionSeperator = Split(thisData, "|")
                    local funct = FunctionSeperator[1]
                    -- Check to see if args is a string or table or nil
                    local args
                    if FunctionSeperator[2] ~= nil then
                        args = Split( FunctionSeperator[2], "/")
                    end
                    if funct == "SetUID" then
--                        Ctrl.UID = args[1]
                        Ctrl.UID = args
                    else
                        if Ctrl.onReceive ~= nil then Ctrl.onReceive( funct, args ) end
                    end
                end
            end
            
            for i, msg in pairs( Ctrl.SendBuffer ) do
                local data, err = Ctrl.ClientSock:send(msg)
                if ( err == "closed" and Ctrl.clientPulse ) then
                    Ctrl.ClientSock = connectToServer( ip, port )
                    data, err = Ctrl.ClientSock:send( msg )
                end
                table.remove( Ctrl.SendBuffer, i )
            end
        end

        Ctrl.clientPulse = timer.performWithDelay( 20, cPulse, 0 )
--        Ctrl.clientPulse = timer.performWithDelay( 100, cPulse, 0 )
        return Ctrl
    end

return Client