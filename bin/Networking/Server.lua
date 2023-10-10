local socket = require( "socket" )
--local JSON = require("json")

local isSocket2 = (string.match( require("socket")._VERSION, "LuaSocket 2" ) ~= nil )

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
--  local socketTest1 = socket.udp6()
--  socketTest1:setpeername( "google.com", 54613 )
--  local testPeerIP = socketTest1:getsockname()
--  if (testPeerIP == "::") then
--    ipv6Test = false
--  end
--end

local function getIP()
    local s = socket.udp()
    s:setpeername( "74.125.115.104", 80 )
    local ip, sock = s:getsockname()
    return ip
end

local function GUID()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
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
        builder = builder..Args
    end
    --print("builder:", builder)
    return builder
end

Server = {}
    Server.Name = ""
    Server.AdvertiseSock = nil
    Server.StartAdvertise = function( serverName, port )
        Server.Name = serverName
        if Server.Advertisebroadcaster == nil then
            local msg = "g00pS3rv3r"
            
            local UDPBroadcaster = socketUDP()
            UDPBroadcaster:setsockname("*", 0) --bind on any availible port and localserver ip address.
            UDPBroadcaster:settimeout(0)
            Server.AdvertiseSock = UDPBroadcaster

            local function broadcast()
                
                Server.AdvertiseSock:setoption( "broadcast", true )  --turn on broadcast
                Server.AdvertiseSock:sendto(msg..Server.Name, "255.255.255.255", port)
                Server.AdvertiseSock:setoption( "broadcast", false )  --turn off broadcast

            end

            Server.Advertisebroadcaster = timer.performWithDelay( 100, broadcast, 0 )
        else
            error("The server is already broadcasting")
        end
    end

    Server.StopAdvertise = function()
      if Server.Advertisebroadcaster then
        timer.cancel( Server.Advertisebroadcaster )
        Server.Advertisebroadcaster = nil
      end
      if Server.AdvertiseSock ~= nil then
          Server.AdvertiseSock:close()
          Server.AdvertiseSock = nil
      end
    end

    Server.StartServer = function( UserName, Port )
        local tcp = socketTCP()
        tcp:bind( getIP(), Port )
        tcp:listen(0)
        local Ctrl = {}
        Ctrl.UID = GUID()
        Ctrl.IsHost = true
        Ctrl.UserName = UserName
        Ctrl.serverSock = tcp
        Ctrl.serverSock:settimeout( 0 )

        Ctrl.clientList = {}
        Ctrl.clientBuffer = {} --[[
            [UID] = {
                ["UID"] = UID,
                ["Socket"] = socket,
                ["SendBuffer"] = { sendBuffer },
                ["UserName"] = UserName
            }
        ]]

        local function find(UserName)
            if UserName == Ctrl.UserName then
                return Ctrl.UID
            end
            for i,v in pairs(Ctrl.clientBuffer) do
                if v["UserName"] == UserName then
                    return v["UID"]
                end
            end
        end

        local function from(socket)
            for i,v in pairs(Ctrl.clientBuffer) do
                if v["Socket"] == socket then
                    return v
                end
            end
        end

        Ctrl.SendTo = function(UIDorUserName, Function, Args)
            local UID = find(UIDorUserName)
            if UID then
                table.insert( Ctrl.clientBuffer[UID]["SendBuffer"], BuildFunction(Function, Args) )
            elseif Ctrl.clientBuffer[UIDorUserName] ~= nil then
                table.insert( Ctrl.clientBuffer[UIDorUserName]["SendBuffer"], BuildFunction(Function, Args) )
            end
        end

        Ctrl.Send = function(Function, Args)
            for i,v in pairs(Ctrl.clientBuffer) do
                table.insert( v["SendBuffer"], BuildFunction(Function, Args) )
            end
        end

        Ctrl.StopServer = function()
            if Ctrl.serverSock ~= nil then
                timer.cancel( Ctrl.serverBroadcaster )
                Ctrl.serverSock:close()
                Ctrl.serverSock = nil
                for i, v in pairs( Ctrl.clientList ) do
                    v:close()
                end
                Ctrl = nil
            end
        end
     
        local function sPulse()
            repeat
                local client = Ctrl.serverSock:accept()
                
                if client then
                    client:settimeout( 0 )
                    table.insert( Ctrl.clientList, client )
                    local ID = GUID()
                    Ctrl.clientBuffer[ID] = {}
                    Ctrl.clientBuffer[ID]["UID"] = ID
                    Ctrl.clientBuffer[ID]["Socket"] = client
                    Ctrl.clientBuffer[ID]["SendBuffer"] = { BuildFunction("SetUID", {ID}, "") }
                    Ctrl.clientBuffer[ID]["UserName"] = ""
                end
            until not client
            
            local ready, writeReady, err = socket.select( Ctrl.clientList, Ctrl.clientList, 0 )
            if err == nil then
                for i=1, #ready do
                    local client = ready[i]
                    local receiveBuffer = {}
                    repeat
                        local data, err = client:receive()
                        if data then
                            table.insert(receiveBuffer, data)
                        end
                    until not data
                    if ( #receiveBuffer > 0 ) then
                        for i, thisData in ipairs( receiveBuffer ) do
                            ---------------------------------------------------------------------------
                            local splitPacket = Split(thisData, "|")
                            local FromUID = from(client)["UID"]     -- Who the packet is sent from
                            local ToUID = splitPacket[1]            -- Who the packet is sent to
                            local Funct = splitPacket[2]            -- Function attached to packet
                            local Args = Split(splitPacket[3], "/") -- Arguments attatched to packet
                            local x = find(ToUID) -- If is a username returns UID if not then null
                            if x then -- if username found
                                ToUID = x -- set UID from username to UID
                            end
                            if Funct == "SetUserName" then
                                Ctrl.clientBuffer[FromUID]["UserName"] = Args
--                                if Ctrl.onReceive ~= nil then Ctrl.onReceive( "UserJoined", Args, Args ) end
                                if Ctrl.onReceive ~= nil then Ctrl.onReceive( "UserJoined", Args, FromUID ) end


--                            elseif Funct == "Ping" then

--                                print(system.getTimer())
--                              if Ctrl.onReceive ~= nil then Ctrl.onReceive( "Ping", Args, FromUID ) end
--                              local data, err = Ctrl.clientBuffer[FromUID]["Socket"]:send( "Ping|"..FromUID.."\n" )

                            elseif Funct == "RemoveClient" then
                                local tcpClient = Ctrl.clientBuffer[FromUID]["Socket"]
                                --local userName = Ctrl.clientBuffer[FromUID]["UserName"]

                                --print("REMOVING")

                                for i, c in pairs( Ctrl.clientList ) do
                                  if c == tcpClient then
                                    table.remove(Ctrl.clientList, i)
                                    if Ctrl.onReceive ~= nil then Ctrl.onReceive( "RemoveClient", i+1, FromUID ) end
                                  end
                                end
                                Ctrl.clientBuffer[FromUID] = nil
                                local data, err = tcpClient:send( "RemoveClient|"..FromUID.."\n" )
                                timer.performWithDelay(500, function() tcpClient:close() end )
 
                            else
                                if ToUID == "." then -- The Send All tag
                                    for i,v in pairs(Ctrl.clientBuffer) do
                                        if client ~= v["Socket"] then
                                            table.insert( v["SendBuffer"], BuildFunction(Funct, Args) )
                                        end
                                    end
                                    if Ctrl.onReceive ~= nil then Ctrl.onReceive( Funct, Args, Ctrl.clientBuffer[FromUID]["UserName"] ) end
                                else
--                                    if UID == Ctrl.UID then
                                    if ToUID == Ctrl.UID then
--                                        if Ctrl.onReceive ~= nil then Ctrl.onReceive( Funct, Args, Ctrl.clientBuffer[FromUID]["UserName"] ) end
                                        if Ctrl.onReceive ~= nil then Ctrl.onReceive( Funct, Args, Ctrl.clientBuffer[FromUID]["UID"] ) end
                                    else
                                        table.insert( Ctrl.clientBuffer[UID]["SendBuffer"], BuildFunction(Funct, Args) )
                                    end
                                end
                            end
                        end
                    end
                end
                
                -- Send to the client
                for ID, Connection in pairs( Ctrl.clientBuffer ) do
                    for i, msg in pairs( Connection["SendBuffer"] ) do
                        -- print("--- Sending: ", i, msg, "---")
                        local data, err = Connection["Socket"]:send( msg )
                    end
                    Connection["SendBuffer"] = {}
                end
            end
        end
     
        Ctrl.serverBroadcaster = timer.performWithDelay( 20, sPulse, 0 )
--        Ctrl.serverBroadcaster = timer.performWithDelay( 100, sPulse, 0 )
        return Ctrl
    end
 
return Server