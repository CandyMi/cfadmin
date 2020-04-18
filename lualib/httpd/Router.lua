local log = require "logging"
local Log = log:new({dump = true, path = 'httpd-Router'})

local aio = require "aio"
local aio_stat = aio.stat

local url = require "url"
local url_decode = url.decode
-- local url_encode = url.encode

local new_tab = require("sys").new_tab

local string = string
local byte = string.byte
local split = string.sub
local find = string.find
local match = string.match
local splite = string.gmatch
local spliter = string.gsub

local type = type
local next = next
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
-- local io_open = io.open

local slash = '\x2f'        -- '/'
local slash2 = '\x2f\x2f'   -- '//'
local point = '\x2e'        -- '.'
local point2 = '\x2e\x2e'   -- '..'

local Router = {
	API = 1,
	USE = 2,
	STATIC = 3,
	WS = 4,
}

local routes = {} -- 存储路由

local static = {} -- 静态文件路由

-- 主要用作分割路径判断.
local function hex_route(route)
	local tab = new_tab(32, 0)
	for r in splite(route, '/([^ /%?]+)') do
    if r ~= '' then
		  tab[#tab + 1] = r
    end
	end
	return tab
end

-- 主要用作分割hash路由查找
local function to_route(route)
	return spliter(route, "([/]+)", '/')
end

-- 检查是路径回退是否超出静态文件根目录
local function check_path_deep (paths)
  -- 检查是否合法路径.
  local head, tail = paths[1], paths[#paths]
  if head == point2 or tail == point or tail == point2 then
    return true
  end
	local deep = 1
  for _, path in ipairs(paths) do
    if path ~= point then
      if path == point2 then
        deep = deep - 1
      else
        deep = deep + 1
      end
    end
		if deep <= 0 then
			return true
		end
	end
	return false
end

local function registery_static (prefix, route_type)
  if next(static) then
    return
  end
  static.prefix = prefix
  static.type = route_type
end

local load_file

local function registery_router (route, class, route_type)
	routes[to_route(route)] = {class = class, type = route_type}
end

local function find_route (method, path)
  path = url_decode(split(path, 1, (find(path, '?') or 0) - 1))
	local t = routes[to_route(path)]
  if t then
    return t.class, t.type
  end
	local prefix, typ = static.prefix, static.type
	if not prefix and not typ then
    return
  end
  -- 非GET/HEAD方法不查找静态文件
  if method ~= 'GET' and method ~= 'HEAD' then
    return
  end
  local tab = hex_route(path)
  -- 凡是找到'../'并且检查路径回退已经超出静态文件根目录返回404
  if check_path_deep(tab) then
    return
  end
  if not load_file then
    load_file = function ( path )
      local filepath = prefix .. url_decode(path)
      local stat = aio_stat(filepath)
      if type(stat) ~= 'table' or stat.mode ~= 'file' then
        return
      end
      return stat.size, filepath, match(path, '.+%.([%a]+)')
    end
  end
  return load_file, typ
end

-- 查找路由
function Router.find(method, path)
	-- 凡是不以'/'开头的path都返回404
	if byte(path) ~= byte(slash) then
		return
	end
	return find_route(method, path)
end

-- 注册静态文件查找路径
function Router.static (...)
	return registery_static(...)
end

-- 注册路由
function Router.registery(route, class, route_type)
	if type(route) ~= 'string' or route == '' then -- 过滤错误的路由输入
		return Log:WARN('Please Do not add empty string in route registery method :)')
	end
	if find(route, slash2) then -- 不允许出现路由出现[//]
		return Log:WARN('Please Do not add [//] in route registery method :)')
	end
	if find(route, '^/%[%w+:.+%]$') then -- 不允许路由注册rest模式.
		return Log:WARN('Please Do not add [/[type:key] in root route :)]')
	end
	return registery_router(route, class, route_type)
end

-- 注销路由
function Router.unregistery(route)
  routes[to_route(route)]=nil
  if routes[to_route(route)] then
    return false
  end
  Log:INFO("路由 ["..route.."] 注册取消..")
	return true
end

return Router
