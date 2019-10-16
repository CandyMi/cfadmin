local concat = table.concat
local type = type

local csv = {}

-- 读取并且解析CSV文件, 格式如下:
--[[
  [1] = [Name1, Name2, Nam3, ..., NameN]
  [2] = [Value1, Value2, Value3, ..., ValueN]
  .
  ..
  ...
  [N] = [Value1, Value2, Value3, ..., ValueN]
]]
-- 规则1: 第一行为所有字段的名称, 第二行开始到第N行是内容;
-- 规则2: 每行不允许出现空格与逗号引号等特殊字符, 空格字符将会被删除掉;
-- 规则3: 打开csv文件失败将返回nil与一个err错误信息.
function csv.loadfile (path)
  if type(path) ~= 'string' or path == '' then
    return nil, "invalid args."
  end
  local file, err = io.open(path, "r")
  if not file then
    return nil, err
  end
  local tab = {}
  for line in file:lines() do
    local items = {}
    for item in line:gmatch("([^,\r\n]+)") do
      if item and item ~= '' then
        items[#items + 1] = item:gsub("[ \"']", "")
      end
    end
    if #items > 0 then
      tab[#tab + 1] = items
    end
  end
  file:close()
  return tab
end

-- 规则同上
function csv.writefile (path, t)
  if type(path) ~= 'string' or path == '' or type(t) ~= 'table' or #t < 1 then
    return nil, "invalid args."
  end
  local file, err = io.open(path, "w")
  if not file then
    return nil, err
  end
  local headers = t[1]
  file:write(concat(headers, ",") .. '\n')
  for index = 2, #t do
    file:write(concat(t[index], ',') .. '\n')
  end
  file:flush()
  file:close()
  return true
end

return csv
