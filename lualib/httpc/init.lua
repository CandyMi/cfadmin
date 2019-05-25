local class = require "class"
local tcp = require "internal.TCP"
local HTTP = require "protocol.http"

local FILEMIME = HTTP.FILEMIME
local RESPONSE_PROTOCOL_PARSER = HTTP.RESPONSE_PROTOCOL_PARSER
local RESPONSE_HEADER_PARSER = HTTP.RESPONSE_HEADER_PARSER

local random = math.random
local find = string.find
local match = string.match
local split = string.sub
local splite = string.gmatch
local spliter = string.gsub
local lower = string.lower
local insert = table.insert
local concat = table.concat
local toint = math.tointeger
local type = type
local assert = assert
local ipairs = ipairs
local tostring = tostring

local CRLF = '\x0d\x0a'
local CRLF2 = '\x0d\x0a\x0d\x0a'

local fmt = string.format

local SERVER = "cf/0.1"

local __TIMEOUT__ = 15

local httpc = {}

local function httpc_response(IO, SSL)
	if not IO then
		return nil, "Can't used this method before other httpc method.."
	end
	local CODE, HEADER, BODY
	local Content_Length
	local content = {}
	local times = 0
	while 1 do
		local data, len
		if SSL == "http" then
			data, len = IO:recv(1024)
		else
			data, len = IO:ssl_recv(1024)
		end
		if not data then
			IO:close()
			return nil, "A peer of remote server close this connection."
		end
		insert(content, data)
		local DATA = concat(content)
		local posA, posB = find(DATA, CRLF2)
		if posB then
			CODE = RESPONSE_PROTOCOL_PARSER(split(DATA, 1, posB))
			HEADER = RESPONSE_HEADER_PARSER(split(DATA, 1, posB))
			if not CODE or not HEADER then
				IO:close()
				return nil, "can't resolvable protocol."
			end
			local Content_Length = toint(HEADER['Content-Length'] or HEADER['content-length'])
			local chunked = HEADER['Transfer-Encoding']
			if not chunked and not Content_Length then
				Content_Length = 0
			end
			if Content_Length then
				if (#DATA - posB) == Content_Length then
					IO:close()
					return CODE, split(DATA, posB+1, #DATA)
				end
				local content = {split(DATA, posB+1, #DATA)}
				while 1 do
					local data, len
					if SSL == "http" then
						data, len = IO:recv(1024)
					else
						data, len = IO:ssl_recv(1024)
					end
					if not data then
						IO:close()
						return CODE, SSL.."[Content_Length] A peer of remote server close this connection."
					end
					insert(content, data)
					local DATA = concat(content)
					if Content_Length == #DATA then
						IO:close()
						return CODE, DATA
					end
				end
			end
			if chunked and chunked == "chunked" then
				local content = {}
				if #DATA > posB then
					local DATA = split(DATA, posB+1, #DATA)
					if find(DATA, CRLF2) then
						local body = {}
						for hex, block in splite(DATA, "([%w]*)\r\n(.-)\r\n") do
							local len = toint(fmt("0x%s", hex))
							if len and len == #block then
								if len == 0 and block == '' then
									IO:close()
									return CODE, concat(body)
								end
								insert(body, block)
							end
						end
					end
					insert(content, DATA)
				end
				while 1 do
					local data, len
					if SSL == "http" then
						data, len = IO:recv(1024)
					else
						data, len = IO:ssl_recv(1024)
					end
					if not data then
						IO:close()
						return CODE, SSL.."[chunked] A peer of remote server close this connection A."
					end
					insert(content, data)
					local DATA = concat(content)
					if find(DATA, CRLF2) then
						local body = {}
						for hex, block in splite(DATA, "([%a%d]*)\r\n(.-)\r\n") do
							local len = toint(fmt("0x%s", hex))
							if len and len == #block then
								if len == 0 and block == '' then
									IO:close()
									return CODE, concat(body)
								end
								insert(body, block)
							end
						end
					end
				end
			end
		end
	end
end

local function IO_CONNECT(IO, PROTOCOL, DOAMIN, PORT)
	local PORT = tonumber(PORT)
	if PROTOCOL == "http" then
		if not PORT or PORT > 65536 or PORT < 1 then
			PORT = 80
		end
		local ok, err = IO:connect(DOAMIN, PORT)
		if not ok then
			IO:close()
			return false, 'httpc 连接失败: '.. DOAMIN ..',' .. PORT
		end
		return true
	end
	if PROTOCOL == "https" then
		if not PORT or PORT > 65536 or PORT < 1 then
			PORT = 443
		end
		local ok = IO:ssl_connect(DOAMIN, PORT)
		if not ok then
			IO:close()
			return false, 'httpc ssl连接失败: '.. DOAMIN ..',' .. PORT
		end
		return true
	end
	IO:close()
	return nil, "IO_CONNECT error! unknow PROTOCOL: "..tostring(PROTOCOL)
end

local function IO_SEND(IO, PROTOCOL, DATA)
	if PROTOCOL == "http" then
		local ok = IO:send(DATA)
		if not ok then
			IO:close()
			return nil, "httpc request get method error"
		end
		return true
	end
	if PROTOCOL == "https" then
		local ok = IO:ssl_send(DATA)
		if not ok then
			IO:close()
			return nil, "httpc ssl request get method error"
		end
		return true
	end
	IO:close()
	return nil, "IO_SEND error! unknow PROTOCOL: "..tostring(PROTOCOL)
end


local function splite_protocol(domain)
	local PROTOCOL, DOMAIN, PATH = match(domain, '(http[s]?)://([^/]+)([/]?.*)')
	if not PROTOCOL or PROTOCOL == '' or not DOMAIN  or DOMAIN == '' then
		return nil, "Invaild protocol"
	end
	if not PATH or PATH == '' then
		PATH = '/'
	end
	local times = 0
	for colon in splite(DOMAIN, ":") do
		times = times + 1
	end
	local PORT
	if times == 1 then
		DOMAIN, PORT = match(DOMAIN, "(.+):([%d]+)")
	elseif times > 1 then
		local domain, port = match(DOMAIN, "%[(.+)%][:]?([%d]*)")
		if domain and port then
			DOMAIN, PORT = domain, port
		end
	end
	return PROTOCOL, DOMAIN, PORT, PATH
end


-- HTTP GET
function httpc.get(domain, HEADER, ARGS, TIMEOUT)

	local PROTOCOL, DOMAIN, PORT, PATH = splite_protocol(domain)
	local port
	if type(PORT) == 'number' and (port ~= 80 or port ~= 443) then
		port = ":"..PORT
	else
		port = ""
	end

	local request = {
		fmt("GET %s HTTP/1.1", PATH),
		fmt("Host: %s", DOMAIN..':'..port),
		'Accept: */*',
		'Accept-Encoding: identity',
		fmt("Connection: keep-alive"),
		fmt("User-Agent: %s", SERVER),
	}
	if ARGS and type(ARGS) == "table" then
		local args = {}
		for _, arg in ipairs(ARGS) do
			assert(#arg == 2, "args need key[1]->value[2] (2 values)")
			insert(args, arg[1]..'='..arg[2])
		end
		request[1] = fmt("GET %s HTTP/1.1", PATH..'?'..concat(args, "&"))
	end
	if HEADER and type(HEADER) == "table" then
		for _, header in ipairs(HEADER) do
			assert(lower(header[1]) ~= 'content-length', "please don't give Content-Length")
			assert(#header == 2, "HEADER need key[1]->value[2] (2 values)")
			insert(request, header[1]..': '..header[2])
		end
	end
	insert(request, CRLF)
	local REQ = concat(request, CRLF)

	local IO = tcp:new():timeout(TIMEOUT or __TIMEOUT__)
	local ok, err = IO_CONNECT(IO, PROTOCOL, DOMAIN, PORT)
	if not ok then
		return ok, err
	end
	local ok, err = IO_SEND(IO, PROTOCOL, REQ)
	if not ok then
		return ok, err
	end
	return httpc_response(IO, PROTOCOL)
end

-- HTTP POST
function httpc.post(domain, HEADER, BODY, TIMEOUT)

	local PROTOCOL, DOMAIN, PORT, PATH = splite_protocol(domain)
	local port
	if type(PORT) == 'number' and (port ~= 80 or port ~= 443) then
		port = ":"..PORT
	else
		port = ""
	end

	local request = {
		fmt("POST %s HTTP/1.1\r\n", PATH),
		fmt("Host: %s\r\n", DOMAIN..':'..port),
		'Accept: */*\r\n',
		'Accept-Encoding: identity\r\n',
		fmt("Connection: keep-alive\r\n"),
		fmt("User-Agent: %s\r\n", SERVER),
		'Content-Type: application/x-www-form-urlencoded\r\n',
	}
	if HEADER and type(HEADER) == "table" then
		for _, header in ipairs(HEADER) do
			assert(string.lower(header[1]) ~= 'content-length', "please don't give Content-Length")
			assert(#header == 2, "HEADER need key[1]->value[2] (2 values)")
			insert(request, header[1]..': '..header[2]..CRLF)
		end
	end
	insert(request, CRLF)

	if BODY and type(BODY) == "table" then
		local body = {}
		for _, b in ipairs(BODY) do
			assert(#b == 2, "if BODY is TABLE, BODY need key[1]->value[2] (2 values)")
			insert(body, fmt("%s=%s", b[1], b[2]))
		end
		insert(request, concat(body, "&"))
		insert(request, #request - 2, fmt("Content-Length: %s\r\n", #request[#request]))
	end
	if BODY and type(BODY) == "string" then
		insert(request, #request, fmt("Content-Length: %s\r\n", #BODY))
		insert(request, BODY)
	end

	local REQ = concat(request)

	local IO = tcp:new():timeout(TIMEOUT or __TIMEOUT__)
	local ok, err = IO_CONNECT(IO, PROTOCOL, DOMAIN, PORT)
	if not ok then
		return ok, err
	end
	local ok, err = IO_SEND(IO, PROTOCOL, REQ)
	if not ok then
		return ok, err
	end
	return httpc_response(IO, PROTOCOL)
end

function httpc.json(domain, HEADER, JSON, TIMEOUT)

	local PROTOCOL, DOMAIN, PORT, PATH = splite_protocol(domain)
	local port
	if type(PORT) == 'number' and (port ~= 80 or port ~= 443) then
		port = ":"..PORT
	else
		port = ""
	end

	assert(type(JSON) == "string", "Please passed A vaild json string.")

	local request = {
		fmt("POST %s HTTP/1.1\r\n", PATH),
		fmt("Host: %s\r\n", DOMAIN..':'..port),
		'Accept: */*\r\n',
		'Accept-Encoding: identity\r\n',
		fmt("Connection: keep-alive\r\n"),
		fmt("User-Agent: %s\r\n", SERVER),
		fmt("Content-Length: %s\r\n", #JSON),
		'Content-Type: application/json\r\n',
	}
	if HEADER and type(HEADER) == "table" then
		for _, header in ipairs(HEADER) do
			assert(lower(header[1]) ~= 'content-length', "please don't give Content-Length")
			assert(#header == 2, "HEADER need key[1]->value[2] (2 values)")
			insert(request, header[1]..': '..header[2]..CRLF)
		end
	end

	insert(request, CRLF)
	insert(request, JSON)

	local REQ = concat(request)

	local IO = tcp:new():timeout(TIMEOUT or __TIMEOUT__)
	local ok, err = IO_CONNECT(IO, PROTOCOL, DOMAIN, PORT)
	if not ok then
		return ok, err
	end
	local ok, err = IO_SEND(IO, PROTOCOL, REQ)
	if not ok then
		return ok, err
	end
	return httpc_response(IO, PROTOCOL)
end

function httpc.file(domain, HEADER, FILES, TIMEOUT)

	local PROTOCOL, DOMAIN, PORT, PATH = splite_protocol(domain)
	local port
	if type(PORT) == 'number' and (port ~= 80 or port ~= 443) then
		port = ":"..PORT
	else
		port = ""
	end

	local request = {
		fmt("POST %s HTTP/1.1\r\n", PATH),
		fmt("Host: %s\r\n", DOMAIN..':'..port),
		'Accept: */*\r\n',
		'Accept-Encoding: identity\r\n',
		fmt("Connection: keep-alive\r\n"),
		fmt("User-Agent: %s\r\n", SERVER),
	}

	if HEADER and type(HEADER) == "table" then
		for _, header in ipairs(HEADER) do
			assert(lower(header[1]) ~= 'content-length', "please don't give Content-Length")
			assert(#header == 2, "HEADER need key[1]->value[2] (2 values)")
			insert(request, header[1]..': '..header[2]..'\r\n')
		end
	end

	if FILES then
		local bd = random(1000000000, 9999999999)
		local boundary_start = fmt("------CFWebService%d", bd)
		local boundary_end   = fmt("------CFWebService%d--", bd)
		insert(request, fmt('Content-Type: multipart/form-data; boundary=----CFWebService%s\r\n', bd))
		local body = {}
		for _, file in ipairs(FILES) do
			insert(body, boundary_start)
			local header = ""
			if file.name and file.filename then
				header = fmt(' name="%s"; filename="%s"', file.name, file.filename)
			end
			insert(body, fmt('Content-Disposition: form-data;%s', header))
			insert(body, fmt('Content-Type: %s\r\n', FILEMIME(file.type or '') or 'application/octet-stream'))
			insert(body, file.file)
		end
		body = concat(body, CRLF)
		insert(request, fmt("Content-Length: %s\r\n", #body + 2 + #boundary_end))
		insert(request, CRLF)
		insert(request, body)
		insert(request, CRLF)
		insert(request, boundary_end)
	end

	local REQ = concat(request)

	local IO = tcp:new():timeout(TIMEOUT or __TIMEOUT__)
	local ok, err = IO_CONNECT(IO, PROTOCOL, DOMAIN, PORT)
	if not ok then
		return ok, err
	end
	local ok, err = IO_SEND(IO, PROTOCOL, REQ)
	if not ok then
		return ok, err
	end
	return httpc_response(IO, PROTOCOL)
end

return httpc
