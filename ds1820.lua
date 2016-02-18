-- ds1820.lua
-- Measure temperature and post data to thingspeak.com

log = true -- is logger on?

--
----
------ XOR - function used for adjusting negative temperature values
function bxor(a, b)
	local r = 0
	for i = 0, 31 do
		if ( a % 2 + b % 2 == 1 ) then
			r = r + 2^i
		end
		a = a / 2
		b = b / 2
	end
	return r
end

--
----
------ Get temperature from DS18B20 
function getTemp()

	local temp = -999 -- default value
	local addr = nil
	local count = 0
	local data = nil
	local pin = 3 -- pin connected to DS18B20 - GPI0

	-- setup gpio pin for oneWire access
	ow.setup(pin)

	-- do search until addr is returned
	repeat
		count = count + 1
		addr = ow.reset_search(pin)
		addr = ow.search(pin)
		tmr.wdclr()
	until((addr ~= nil) or (count > 100))

	-- if addr was never returned, abort
	if (addr == nil) then
		if (log) print('DS18B20 not found')
		return temp
	end

	if (log) 
		print(string.format("Addr:%02X-%02X-%02X-%02X-%02X-%02X-%02X-%02X", addr:byte(1), addr:byte(2), addr:byte(3), addr:byte(4), addr:byte(5), addr:byte(6), addr:byte(7), addr:byte(8)))

	-- validate addr checksum
	crc = ow.crc8(string.sub(addr, 1, 7))
	if (crc ~= addr:byte(8)) then
		if (log) print('DS18B20 addr CRC failed');
		return temp
	end

	if not((addr:byte(1) == 0x10) or (addr:byte(1) == 0x28)) then
	if (log) print('DS18B20 not found')
		return temp
	end

	ow.reset(pin) -- reset onewire interface
	ow.select(pin, addr) -- select DS18B20
	ow.write(pin, 0x44, 1) -- store temp in scratchpad
	tmr.delay(1000000) -- wait 1 sec

	present = ow.reset(pin) -- returns 1 if dev present
	if present ~= 1 then
		if (log) print('DS18B20 not present')
		return temp
	end

	ow.select(pin, addr) -- select DS18B20 again
	ow.write(pin, 0xBE, 1) -- read scratchpad

	-- rx data from DS18B20
	data = nil
	data = string.char(ow.read(pin))
	for i = 1, 8 do
		data = data .. string.char(ow.read(pin))
	end

	if (log) 
		print (string.format("Data:%02X-%02X-%02X-%02X-%02X-%02X-%02X-%02X", data:byte(1), data:byte(2), data:byte(3), data:byte(4), data:byte(5), data:byte(6), data:byte(7), data:byte(8)))

	-- validate data checksum
	crc = ow.crc8(string.sub(data,1,8))
	if (crc ~= data:byte(9)) then
		if (log) print('DS18B20 data CRC failed')
		return temp
	end

	-- now change it from negative values
	temp = (data:byte(1) + data:byte(2) * 256)
	
	-- first bit is 1
	if (temp > 32768) then
		temp = (bxor(temp, 0xffff)) + 1
		temp = (-1) * temp
	end

	temp = temp * 625
	
	return temp
		    
end -- getTemp

--
----
------ Get temp and send data to thingspeak.com
function sendData()

	temp = getTemp()
	if (log) print("Measured temp="..temp.." Celsius")
		
	-- conection to thingspeak.com
	if (log) print("Sending data to thingspeak.com")
	conn=net.createConnection(net.TCP, 0) 
	conn:on("receive", function(conn, payload) print(payload) end)
	
	-- api.thingspeak.com 184.106.153.149
	conn:connect(80,'184.106.153.149') 
	conn:send("GET /update?key=N0AQKXUUY2MTFXWV&field1="..temp.." HTTP/1.1\r\n") 
	conn:send("Host: api.thingspeak.com\r\n") 
	conn:send("Accept: */*\r\n") 
	conn:send("User-Agent: Mozilla/4.0 (compatible; esp8266 Lua; Windows NT 5.1)\r\n")
	conn:send("\r\n")
	conn:on("sent",function(conn)
		if (log) print("Closing connection")
		conn:close()
	end)
	conn:on("disconnection", function(conn)
		if (log) print("Got disconnection...")
	end)
end --sendData

--
----
------ Send data every X ms senconds to thing speak
tmr.alarm(0, 60000, 1, function() sendData() end )
