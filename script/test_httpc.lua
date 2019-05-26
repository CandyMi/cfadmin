local cf = require "cf"
local httpc = require "httpc"
local json = require "json"

local ti = cf.timeout(2, function ( ... )
  cf.fork(function ( ... )
    -- GET请求: 在参数固定的情况下可以直接写在url内
    local code, body = httpc.get("http://localhost:8080/api?page=1&limit=10", {{"Auth", "admin"}})
    print(code, body)

    -- GET请求: 在参数为动态的情况下可以提供请求数组由httpc库进行拼接
    local code, body = httpc.get("http://[::1]:8080/api", {{"Auth", "admin"}}, {{'page', 1}, {'limit', 10}})
    print(code, body)

    -- POST HEADER 为数组, BODY为数组
    local code, body = httpc.post("http://[::ffff:127.0.0.1]:8080/api", {{"Auth", "admin"}}, {{'page', 1}, {'limit', 10}})
    print(code, body)

    -- POST HEADER 为数组, BODY为字符串
    local code, body = httpc.post("http://127.0.0.1:8080/api", {{"Auth", "admin"}}, "page=1&limit=10")
    print(code, body)

    -- http json请求示例
    local code, body = httpc.json("http://localhost:8080/api", {{"Auth", "admin"}}, json.encode({page=1, limit=10}))
    print(code, body)

    -- http 上传文件示例
    local code, body = httpc.file('http://localhost:8080/view', nil, {
        {name='1', filename='1.jpg', file='1', type='abc'},
        {name='2', filename='2.jpg', file='2', type='abc'},
        })
    print(code, body)
  end)
end)
