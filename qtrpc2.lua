do

local message_types = {
	[0] = 'Function', 
	[1] = 'QtRpc Internal', 
	[2] = 'Event', 
	[3] = 'Return', 
	[4] = 'Invalid'
}

local return_value_types = {
	[0] = 'Variant',
	[1] = 'Error',
	[2] = 'Service',
	[3] = 'Asyncronous'
}

function table.key_to_str ( k )
  if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
    return k
  else
    return "[" .. table.val_to_str( k ) .. "]"
  end
end

function table.tostring( tbl )
  local result, done = {}, {}
  for k, v in ipairs( tbl ) do
    table.insert( result, table.val_to_str( v ) )
    done[ k ] = true
  end
  for k, v in pairs( tbl ) do
    if not done[ k ] then
      table.insert( result,
        table.key_to_str( k ) .. "=" .. tostring( v ) )
    end
  end
  return "{" .. table.concat( result, "," ) .. "}"
end

local meta_type_loaders = {}

local function readUtf16String(buffer, i)
	local len = buffer(i, 4):int()
	return buffer(i+4, len):ustring(), 4+len
end

local function readString(buffer, i)
	local len = buffer(i, 4):int()
	return buffer(i+4, len-1):string(), 4+len
end

local Variant = {
	meta_types = {
		[1] = 'bool',
		[2] = 'int',
		[3] = 'uint',
		[9] = 'QVariantList',
		[10] = 'QString',
		[11] = 'QStringList',
		[43] = 'void'
	}
}

function Variant:__tostring()
	if self.null then
		return self.type .. '(NULL)'
	else
		return self.type .. '(' .. (self.value or '') .. ')'
	end
end

function Variant.read(buffer, start)
	local i = start
	local len = 0
	local var = {}
	local type_id = buffer(i, 4):int()
	i = i + 4
	var.null = buffer(i, 1):int() == 1
	i = i + 1
	if type_id == 127 then
		var.type, len = readString(buffer, i)
		i = i + len
	else
		var.type = Variant.meta_types[type_id] or 'Unknown QVariant id=' .. type_id	
	end

	if var.null then 
		return setmetatable(var, Variant), i - start
	end

	if type_id == 1 then -- bool
		var.value = buffer(i, 1):int()
		i = i + 1
	elseif type_id == 2 then -- int
		var.value = buffer(i, 4):int()
		i = i + 4
	elseif type_id == 3 then -- uint
		var.value = buffer(i, 4):uint()
		i = i + 4
	elseif type_id == 9 then -- QVariantList
		local count = buffer(i, 4):int()
		i = i + 4
		var.value = ''
		for var_index = 1, count do
			local subvar, len = Variant.read(buffer, i)
			i = i + len
			var.value = var.value .. tostring(subvar)
			if var_index ~= count then var.value = var.value .. ',' end
		end 
	elseif type_id == 10 then -- QString
		var.value, len = readUtf16String(buffer, i)
		i = i + len
		var.value = '"' .. var.value .. '"'
	elseif type_id == 11 then -- QStringList
		local count = buffer(i, 4):int()
		i = i + 4
		var.value = ''
		for str_index = 1, count do
			local str, len = readUtf16String(buffer, i)
			i = i + len
			var.value = var.value .. '"' .. str .. '"'
			if str_index ~= count then var.value = var.value .. ',' end
		end
	elseif type_id == 127 then -- custom meta type
		local loader = meta_type_loaders[var.type]
		if loader then
			var.value, len = loader(buffer, i)
			i = i + len
		end
	end

	return setmetatable(var, Variant), i - start
end

local function readVariantMap(buffer, start)
	local len = 0
	local i = start
	local count = buffer(i, 4):int()
	local map = {}
	i = i + 4
	for pair_index = 1, count do
		local key, len = readUtf16String(buffer, i)
		i = i + len
		local value, len = Variant.read(buffer, i)
		i = i + len
		map[key] = value
	end
	return map, i-start
end

meta_type_loaders['QtRpc::AuthToken'] = function(buffer, start)
	local len = 0
	local i = start
	local defaultToken = buffer(i, 1):int() == 1
	i = i + 1
	local clientData, len = readVariantMap(buffer, i)
	i = i + len
	local serverData, len = readVariantMap(buffer, i)
	i = i + len
	return 'defaultToken=' .. tostring(defaultToken) .. ', clientData=' .. table.tostring(clientData) .. ', serverData=' .. table.tostring(serverData), i-start
end

local Signature = {}

function Signature:__tostring()
	local result = self.name .. '('
	for i, v in ipairs(self.args) do
		if i ~= 1 then result = result .. ',' end
		result = result .. self.args[i]
	end
	result = result .. ')'
	return result
end

function Signature.read(buffer, start)
	local sig = {}
	local len = 0
	local i = start

	sig.name, len = readUtf16String(buffer, i)
	i = i + len

	sig.args = {}
	local args_count = buffer(i, 4):int()
	i = i + 4
	for arg_index = 1, args_count do
		sig.args[arg_index], len = readUtf16String(buffer, i)
		i = i + len
	end

	return setmetatable(sig, Signature), i - start
end

local ReturnValue = {}

function ReturnValue:__tostring()
	if self.type == 0 then -- Variant
		return tostring(self.var)
	elseif self.type == 1 then -- Error
		return 'Error=(#' .. self.err_number .. ', ' .. self.err_string .. ')'
	elseif self.type == 2 then -- Service
		return 'ServiceId=' .. tostring(self.service_id)
	elseif self.type == 3 then -- Async
		return 'Async'
	end
	return ''
end

function ReturnValue.read(buffer, start)
	local len = 0
	local i = start
	local ret = {}
	ret.type = buffer(i, 4):int()
	i = i + 4
	if ret.type ==  0 then -- Variant
		ret.var, len = Variant.read(buffer, i)
		i = i + len
	elseif ret.type == 1 then -- Error
		ret.err_number = buffer(i, 4):int()
		i = i + 4
		ret.err_string, len = readUtf16String(buffer, i)
		i = i + len
	elseif ret.type == 2 then -- Service
		ret.service_id = buffer(i, 4):int()
		i = i + 4
	end
	return setmetatable(ret, ReturnValue), i-start
end

local function readArguments(buffer, start)
	local i = start
	local args = {}
	local args_count = buffer(i, 4):int()
	i = i + 4
	for arg_index = 1, args_count do
		local len = 0
		args[arg_index], len = Variant.read(buffer, i)
		args[arg_index].tvbr = buffer(i, len)
		i = i + len
	end
	return args, i - start
end

function dissect_qtrpc2_packet(buffer,pinfo,tree,start,len)
	local len = 0
	local i = start

	local message_type = buffer(i,4)
	i = i + 4

	tree:add(message_type, "Message type: " .. message_types[message_type:int()])

	if message_type():int() == 4 then
		 return
	end

	if message_type():int() == 0 or message_type():int() == 2 then
		local service_id = buffer(i, 4)
		i = i + 4
	end

	local id = buffer(i, 4)
	i = i + 4

	tree:add(id, "Id: " .. id:int())

	if message_type():int() == 0 or message_type():int() == 1 or message_type():int() == 2 then
		local sig, len = Signature.read(buffer, i)
		tree:add(buffer(i, len), "Function: " .. tostring(sig))
		i = i + len

		local args, len = readArguments(buffer, i)
		local args_tree = tree:add(buffer(i, len), "Arguments")
		for k, v in ipairs(args) do
			args_tree:add(v.tvbr, tostring(v))
		end
		i = i + len
	elseif message_type():int() == 3 then -- ReturnValue
		local ret, len = ReturnValue.read(buffer, i)
		local return_tree = tree:add(buffer(i, len), 'ReturnValue: ' .. tostring(ret))
		i = i + len
	end
end

local qtrpc2_proto = Proto("qtrpc2", "QtRpc2 Protocol")

function qtrpc2_proto.dissector(buffer,pinfo,tree)
	local i = 0

	local qtrpc2_tree = nil
	local message_count = 0

	while i + 12 < buffer:len() do
		local message_size = buffer(i,8)
		i = i + 8

		local magic = buffer(i,4)
		i = i + 4

		if tostring(magic) == '1234abcd' then
			pinfo.cols.protocol = "QtRpc2"
			if not qtrpc2_tree then qtrpc2_tree = tree:add(qtrpc2_proto,buffer(),"QtRpc2 Protocol Data") end
			
			local message = buffer(i, message_size:int64():tonumber() - magic:len())
	
			local message_tree = qtrpc2_tree:add(message, "QtRpc2 Message (" .. message:len() .. " bytes)")
			dissect_qtrpc2_packet(buffer,pinfo,message_tree,message:offset(),message:len())
			i = i + message:len()
			message_count = message_count + 1
		end  
	end

	if message_count > 0 then
		pinfo.cols.info = message_count .. ' messages'
	end
end

local tcp_table = DissectorTable.get("tcp.port")
for port = 1000, 25000 do
	tcp_table:add(port, qtrpc2_proto)
end

end