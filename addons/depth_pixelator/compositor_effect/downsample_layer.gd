class_name DownsampleLayer
extends RefCounted

var layer_id: int = 0
var color_buffer: RID = RID()
var depth_buffer: RID = RID()
var layer_data_buffer: RID = RID()

func free_rids(rd: RenderingDevice) -> void:
	if color_buffer.is_valid():
		rd.free_rid(color_buffer)
	if depth_buffer.is_valid():
		rd.free_rid(depth_buffer)
