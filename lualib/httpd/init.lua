local HTTP = require "protocol.http"
local HTTPD = require "httpd.Router"
local tcp = require "internal.TCP"
local class = require "class"
local log = require "logging"
local cf = require "cf"

local sys = require("sys")
local os_date = sys.date

local type = type
local ipairs = ipairs

local fmt = string.format
local match = string.match
local io_write = io.write
local toint = math.tointeger

-- 请求解析
local EVENT_DISPATCH = HTTP.EVENT_DISPATCH

-- 注册HTTP路由与静态文件
local HTTP_STATIC_REGISTERY = HTTPD.static
local HTTP_ROUTE_REGISTERY = HTTPD.registery
local HTTP_ROUTE_UNREGISTERY = HTTPD.unregistery


local httpd = class("httpd")

function httpd:ctor(opt)
    self.API = HTTPD.API
    self.USE = HTTPD.USE
    self.sock = tcp:new()
end

-- 用来注册WebSocket对象
function httpd:ws(route, class)
    if route and type(class) == "table" then
        HTTP_ROUTE_REGISTERY(route, class, HTTPD.WS)
    end
end

-- 用来注册接口
function httpd:api(route, class)
    if route and (type(class) == "table" or type(class) == "function")then
        HTTP_ROUTE_REGISTERY(route, class, HTTPD.API)
    end
end

-- 用来注册普通路由
function httpd:use(route, class)
    if route and (type(class) == "table" or type(class) == "function") then
        HTTP_ROUTE_REGISTERY(route, class, HTTPD.USE)
    end
end

-- 批量路由注册
function httpd:group(target, prefix, array)
    assert((target == self.API or target == self.USE) and type(prefix) == 'string' and type(array) == 'table' , "注册路由组失败")
    for _, route in ipairs(array) do
        local r, c = route['route'], route['class']
        if target == self.USE then
            self:use(prefix..r, c)
        else
            self:api(prefix..r, c)
        end
    end
end

-- 取消路由注册
function httpd:unregistery(route)
  if HTTP_ROUTE_UNREGISTERY(route) then
    return true
  else
    return false
  end
end

-- 最大URI长度
function httpd:max_path_size(path_size)
    if type(path_size) == 'number' then
        self.__max_path_size = path_size
    end
end

-- 最大Header长度
function httpd:max_header_size(header_size)
    if type(header_size) == 'number' then
        self.__max_header_size = header_size
    end
end

-- 最大Body长度
function httpd:max_body_size(body_size)
    if type(body_size) == 'number' then
        self.__max_body_size = body_size
    end
end

-- 在路由函数被执行之后执行此方法
function httpd:before(func)
    if type(func) == 'function' then
        self._before_func = func
    end
end

-- 可自定义Server Name
function httpd:server_name(server)
    if type(server) == "string" then
        self.__server = server
    end
end

-- 连接保持时间
function httpd:timeout(timeout)
    if type(timeout) == "number" and timeout > 0 then
        self.__timeout = timeout
    end
end

-- 开启跨域支持
function httpd:enable_cros(timeout)
  if toint(timeout) and toint(timeout) > 0 then
    self.__enable_cros_timeout = toint(timeout)
  else
    self.__enable_cros_timeout = '86400'
  end
end

-- 开启gzip压缩支持
function httpd:enable_gzip()
  self.__enable_gzip = true
end

-- 是否记录解析cookie
function httpd:enable_cookie ()
  self.__cookie = true
end

-- 设置Cookie加密Key
function httpd:cookie_secure (secure)
  if type(secure) == 'string' and secure ~= '' then
    self.__cookie_secure = secure
  end
end

-- 注册静态文件读取路径, foldor是一个目录, ttl是静态文件缓存周期
function httpd:static(foldor, ttl)
  if not self.foldor then
    self.foldor = foldor or 'static'
    if ttl and ttl > 0 then
        self.ttl = ttl
    end
    return HTTP_STATIC_REGISTERY(self.foldor, HTTPD.STATIC)
  end
end

-- 记录日志到文件
function httpd:log(path)
  if type(path) == 'string' and path ~= '' then
    self.logging = log:new({ dump = true, path = path })
  end
end

-- 关闭所有日志
function httpd:nolog( disable )
  -- disable指定为true后本机将不会生成任何请求日志, 这样能有利于框架提升更高的性能.
  self.CLOSE_LOG = disable
end

-- LOG_FMT用于构建日志格式
local LOG_FMT = "[%s] - %s - %s - %s - %s - %d - req_time: %0.6f/Sec\n"

function httpd:tolog(code, path, ip, ip_list, method, speed)
  if self.CLOSE_LOG then
    return
  end
  local now = os_date("%Y/%m/%d %H:%M:%S")
  if self.logging then
    self.logging:dump(fmt(LOG_FMT, now, ip, ip_list, path, method, code, speed))
  end
  if io.type(io.output()) == 'file' then
    io_write(fmt(LOG_FMT, now, ip, ip_list, path, method, code, speed))
  end
end

-- 监听请求
function httpd:listen(ip, port, backlog)
  assert(type(ip) == 'string' and toint(port), "httpd error: invalid ip or port")
  self.ip = ip
  self.port = port
  self.sock:set_backlog(toint(backlog))
  return assert(self.sock:listen(ip or "0.0.0.0", toint(port), function (fd, ipaddr)
      return EVENT_DISPATCH(fd, match(ipaddr, '^::[f]+:(.+)') or ipaddr, self)
  end))
end

-- 监听unixsock
function httpd:listenx(unix_domain_path, backlog)
  assert(type(unix_domain_path) == 'string' and unix_domain_path ~= '', "httpd error: invalid unix domain path")
  self.unix_domain_path = unix_domain_path
  self.sock:set_backlog(toint(backlog))
  return assert(self.sock:listen_ex(unix_domain_path, true, function (fd, ipaddr)
    return EVENT_DISPATCH(fd, match(ipaddr, '^::[f]+:(.+)') or ipaddr, self)
  end))
end

-- 正确的运行方式
function httpd:run()
  if self.ip and self.port then
    if self.logging then
      self.logging:dump(fmt('[%s] [INFO] httpd listen: %s:%s \n', os_date("%Y/%m/%d %H:%M:%S"), "0.0.0.0", self.port))
    end
    io_write(fmt('\27[32m[%s] [INFO]\27[0m httpd listen: %s:%s \n', os_date("%Y/%m/%d %H:%M:%S"), "0.0.0.0", self.port))
  end

  if self.unix_domain_path then
    if self.logging then
      self.logging:dump(fmt('[%s] [INFO] httpd listen: %s\n', os_date("%Y/%m/%d %H:%M:%S"), self.unix_domain_path))
    end
    io_write(fmt('\27[32m[%s] [INFO]\27[0m httpd listen: %s\n', os_date("%Y/%m/%d %H:%M:%S"), self.unix_domain_path))
  end

  if self.logging then
    self.logging:dump(fmt('[%s] [INFO] httpd Web Server Running...\n', os_date("%Y/%m/%d %H:%M:%S")))
  end
  io_write(fmt('\27[32m[%s] [INFO]\27[0m httpd Web Server Running...\n', os_date("%Y/%m/%d %H:%M:%S")))
  return cf.wait()
end

return httpd
