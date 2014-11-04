qtrpc2_proto = Proto("qtrpc2", "QtRpc2 Protocol")

function qtrpc2_proto.dissector(buffer,pinfo,tree)
    if buffer(0,3):bytes() == ByteArray.new('50 52 49') then
        pinfo.cols.protocol = "QtRpc2"
        local subtree = tree:add(qtrpc2_proto,buffer(),"QtRpc2 Protocol Data")
        subtree:add(buffer(0,2),"The first two bytes: " .. buffer(0,2):uint())
        subtree = subtree:add(buffer(2,2),"The next two bytes")
        subtree:add(buffer(2,1),"The 3rd byte: " .. buffer(2,1):uint())
        subtree:add(buffer(3,1),"The 4th byte: " .. buffer(3,1):uint())
    end
end

tcp_table = DissectorTable.get("tcp.port")
for i,port in ipairs{4888,4889,4890,4891,9999} do
	tcp_table:add(port, qtrpc2_proto)
end
