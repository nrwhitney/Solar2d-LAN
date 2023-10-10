# Solar2d-LAN
Client/Server LAN library for Solar-2D


Server UDP broadcast now works.
Correctly binds TCP socket to the master IP and Port and sets listen mode transforming it into a server object.
Adds FromUID parameter to server onReceive function to determine incoming data source.
Adds server function to remove disconnected clients and close thier sockets.
Corrects various bugs allowing the functions to be more easily used.
Removed JSON library invocation.
Removed unnecessary options which could possibly cause issues.
