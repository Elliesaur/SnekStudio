extends Mod_Base

var bind_ip_address : String = "127.0.0.1"
var bind_port : int = 39570
var vmc_receiver_enabled : bool = false
var client_ip_address : String = "127.0.0.2"
var client_port : int = 39539
var vmc_sender_enabled : bool = false
var vrc_sender_enabled : bool = false
var vmc_send_mirrored_arms : bool = false
var client_send_rate_limit_ms : int = 50
var client_vmc_protocl_version_setting : Array
var curr_client_send_time : float
var ntp_start_date : Dictionary
var ntp_start_unix : int

var blend_shape_last_values = {}
var overridden_blend_shape_values = {} # FIXME: Make this more general-purpose

var joint_names = [
	"Hips",
	"Spine",
	"Chest",
	"UpperChest",
	"Neck",
	"Head",
	"LeftEye",
	"RightEye",
	"Jaw",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"LeftToes",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
	"RightToes",
	"LeftShoulder",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightShoulder",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftThumbProximal",
	"LeftThumbIntermediate",
	"LeftThumbDistal",
	"LeftIndexProximal",
	"LeftIndexIntermediate",
	"LeftIndexDistal",
	"LeftMiddleProximal",
	"LeftMiddleIntermediate",
	"LeftMiddleDistal",
	"LeftRingProximal",
	"LeftRingIntermediate",
	"LeftRingDistal",
	"LeftLittleProximal",
	"LeftLittleIntermediate",
	"LeftLittleDistal",
	"RightThumbProximal",
	"RightThumbIntermediate",
	"RightThumbDistal",
	"RightIndexProximal",
	"RightIndexIntermediate",
	"RightIndexDistal",
	"RightMiddleProximal",
	"RightMiddleIntermediate",
	"RightMiddleDistal",
	"RightRingProximal",
	"RightRingIntermediate",
	"RightRingDistal",
	"RightLittleProximal",
	"RightLittleIntermediate",
	"RightLittleDistal"
]
var vrc_joint_names = [
	"Hips",
	"Chest",
	"Head",
]
func _ready():
	ntp_start_date = Time.get_datetime_dict_from_datetime_string("1900-01-01T00:00:00Z", false)
	ntp_start_unix = Time.get_unix_time_from_datetime_dict(ntp_start_date)
	
	add_setting_group("vmc_receiving", "VMC Receiving")
	add_setting_group("vmc_sending", "VMC Sending")
	
	# VMC Receiving
	add_tracked_setting("bind_ip_address", "Receiver IP address", {}, "vmc_receiving")
	add_tracked_setting("bind_port", "Receiver port", {}, "vmc_receiving")
	add_tracked_setting("vmc_receiver_enabled", "Receiver enabled", {}, "vmc_receiving")
	
	# VMC Sending
	add_tracked_setting("client_ip_address", "Sender IP address", {}, "vmc_sending")
	add_tracked_setting("client_port", "Sender port", {}, "vmc_sending")
	add_tracked_setting("client_send_rate_limit_ms", "Send rate (ms)", {}, "vmc_sending")
	add_tracked_setting("client_vmc_protocl_version_setting", "VMC Protocol Version", { 
			"allow_multiple": false, 
			"combobox": true, 
			"values": ["v2.3-2.7", "v2.8"]
		}, "vmc_sending")
	add_tracked_setting("vmc_send_mirrored_arms", "Send mirrored arms", {}, "vmc_sending")
	add_tracked_setting("vmc_sender_enabled", "Sender enabled", {}, "vmc_sending")
	# FIXME: New grouping for VRChat Sending
	add_tracked_setting("vrc_sender_enabled", "VRChat sender enabled", {}, "vmc_sending")

	update_settings_ui()

func load_after(_settings_old : Dictionary, _settings_new : Dictionary):
	$KiriOSCServer.change_port_and_ip(bind_port, bind_ip_address)
	if _settings_old["vmc_receiver_enabled"] != _settings_new["vmc_receiver_enabled"]:
		if vmc_receiver_enabled:
			$KiriOSCServer.start_server()
		else:
			$KiriOSCServer.stop_server()
	$KiriOSCClient.change_port_and_ip(client_port, client_ip_address)
	if _settings_old["vmc_sender_enabled"] != _settings_new["vmc_sender_enabled"]:
		if vmc_sender_enabled:
			$KiriOSCClient.start_client()
		else:
			$KiriOSCClient.stop_client()

func scene_shutdown() -> void:
	get_app().get_controller().reset_skeleton_to_rest_pose()
	get_app().get_controller().reset_blend_shapes()

func _on_OSCServer_message_received(address_string, arguments):

	var model : Node3D = get_app().get_model()
	var skeleton : Skeleton3D = get_app().get_skeleton()
	var model_controller : Node3D = get_app().get_node("ModelController")
	
	if address_string == "/VMC/Ext/Bone/Pos":
	
		var actual_bone_name = arguments[0]

		# We may have to rename some thumb bone names, depending on whether we
		# have a VRM 1.0 or 0.0 model.
		if arguments[0].begins_with("LeftThumb") or arguments[0].begins_with("RightThumb"):
			if model_controller.find_mapped_bone_index("LeftThumbMetacarpal") != -1:
				# We have the metacarpal bone, so assume VRM 1.0.
				var bone_without_side = ""
				var bone_side = ""
				if arguments[0].begins_with("Left"):
					bone_without_side = arguments[0].substr(4)
					bone_side = "Left"
				else:
					bone_without_side = arguments[0].substr(5)
					bone_side = "Right"
				#print("BONE WITHOUT SIDE: ", bone_without_side)
				
				var converted_bone_without_side = bone_without_side
				if bone_without_side == "ThumbProximal":
					converted_bone_without_side = "ThumbMetacarpal"
				if bone_without_side == "ThumbIntermediate":
					converted_bone_without_side = "ThumbProximal"
				
				actual_bone_name = bone_side + converted_bone_without_side

		var bone_index =  model_controller.find_mapped_bone_index(actual_bone_name)


		# FIXME: If we want to actually handle bone translation offsets, we
		# need to handle this in the correct coordinate space. Right now
		# enabling it will just double-up translation and look wrong.
		#var origin = Vector3(arguments[1], arguments[2], arguments[3])

		# FIXME: Currently we're rotation-only.
		var origin = Vector3(0.0, 0.0, 0.0) # Use this for rotation-only.

		# We have to flip around some of the rotation axes directly in the
		# quaternion here to account for the different coordinate space.
		#var rot = Quaternion(-arguments[4], -arguments[5], arguments[6], arguments[7])
		
#		var t = int(Time.get_unix_time_from_system())
#		if t & 1:
#			arguments[4] = -arguments[4]
#		if t & 2:
#			arguments[5] = -arguments[5]
#		if t & 4:
#			arguments[6] = -arguments[6]
#		if t & 8:
#			arguments[7] = -arguments[7]
		
		#print(t)
		
		var rot = Quaternion(arguments[4], -arguments[5], -arguments[6], arguments[7]).normalized()
		#rot = $Model/GeneralSkeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion() #Quaternion(0.0, 0.0, 0.0, 1.0) #rot.slerp(Quaternion(0.0, 0.0, 0.0, 1.0), 0.1)
		#var rot = Quaternion(0.0, 0.0, 0.0, 1.0) #rot.slerp(Quaternion(0.0, 0.0, 0.0, 1.0), 0.1)
		
		#var rot = Quaternion(0.0, arguments[6], arguments[5], 0.0)
		
		#rot.w = sqrt(1.0 - (rot.x * rot.x + rot.y * rot.y + rot.z * rot.z))
		
#		var rot = Quaternion(0.0, 0.0, 0.0, 1.0)
#		#if arguments[0].to_lower() == "rightlowerarm" || arguments[0].to_lower() == "rightupperarm":
#			#rot = Quaternion(0.707, 0.0, 0.0, 0.707).normalized()
#			#print(arguments.slice(4, 8))
#
#			#rot = Quaternion(0.0, , 0.0, 0.0)
#			#rot.w = sqrt(1.0 - (rot.x * rot.x + rot.y * rot.y + rot.z * rot.z))
#
		#rot = Quaternion(arguments[6], arguments[4], arguments[5], 0.0)
#		rot.w = sqrt(1.0 - (rot.x * rot.x + rot.y * rot.y + rot.z * rot.z))
#		if arguments[7] < 0.0:
#			rot.w = -rot.w
		
		#print([arguments[0], $Model/GeneralSkeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()])
		
		if bone_index != -1:

			var new_transform : Transform3D = \
#				$Model/GeneralSkeleton.get_bone_rest(bone_index) * \
				skeleton.get_bone_rest(bone_index) * \
				Transform3D(
					skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion()).inverse() * \
				Transform3D(
					Basis(rot),
					origin) * \
				Transform3D(
					skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion())

			skeleton.set_bone_pose_rotation(
				bone_index, new_transform.basis.get_rotation_quaternion())
		else:
			print("NO BONE FOUND FOR VMC THING: ", actual_bone_name)

	# -------------------------------------------------------------------------
	# Blend shapes

	if address_string == "/VMC/Ext/Blend/Val":
		blend_shape_last_values[arguments[0].to_upper()] = arguments[1]

	# Merge blend shapes with overridden stuff.
	var combined_blend_shape_last_values = blend_shape_last_values.duplicate()
	for k in overridden_blend_shape_values.keys():
		if k in combined_blend_shape_last_values:
			combined_blend_shape_last_values[k] = max(
				overridden_blend_shape_values[k],
				combined_blend_shape_last_values[k])
		else:
			combined_blend_shape_last_values[k] =  overridden_blend_shape_values[k]

	if address_string == "/VMC/Ext/Blend/Apply":

		var anim_path_maximums = {}
		var anim_player : AnimationPlayer = model.get_node("AnimationPlayer")

		if anim_player:

			# Figure out the maximum blend shape values for each animation.
			for anim_name in combined_blend_shape_last_values.keys():
	
				# FIXME: Hack hack hack hack hack
				#   This is a hack added on 2023-10-26 so my model can work
				#   tomorrow after I made the silly mistake of updating the VRM
				#   addon.
				var name_mapping_so_this_works_tomorrow = {
					"EYES_SHRUNK" : "Eyes_Shrunk",
					"CLIPBOARD_OPEN" : "Clipboard_Open",
					"BLUSH" : "Blush",
					"TONGUE 1" : "Tongue 1",
					"TONGUE 2" : "Tongue 2",
					"LOOKLEFT" : "lookLeft",
					"LOOKRIGHT" : "lookRight",
					"LOOKUP" : "lookUp",
					"LOOKDOWN" : "lookDown",
					"BROWS DOWN" : "Brows down",
					"BROWS UP" : "Brows up",
					"SORROW" : "sad",
					"NEUTRAL" : "neutral",
					"JOY" : "happy",
					"BLINK" : "blink",
					"A" : "aa",
					"E" : "ee",
					"I" : "ih",
					"O" : "oh",
					"U" : "ou" }


				# Skip any animations that don't exist in this VRM.				
				var full_anim_name = anim_name
				if full_anim_name in name_mapping_so_this_works_tomorrow:
					full_anim_name = name_mapping_so_this_works_tomorrow[full_anim_name]
				if not (full_anim_name in anim_player.get_animation_list()):
					#print("NAME: ", anim_name)
					#print(anim_player.get_animation_list())
					continue
					
				var anim = anim_player.get_animation(full_anim_name)
				
				if not anim:
					continue
				
				# Iterate through every track on the animation.
				#print("Anim ", anim_name, " track count: ", anim.get_track_count())
				for track_index in range(0, anim.get_track_count()):
					var anim_path : NodePath = anim.track_get_path(track_index)

					#print("  track: ", anim.track_get_path(track_index))

					# Create the key if it does not exist.
					if not (anim_path in anim_path_maximums.keys()):
						anim_path_maximums[anim_path] = 0.0
					
					# Record max value.
					anim_path_maximums[anim_path] = max(
						anim_path_maximums[anim_path],
						combined_blend_shape_last_values[anim_name])
					
			# Iterate through every max animation value and set it on the
			# appropriate blend shape on the object.
			var anim_root = anim_player.get_node(anim_player.root_node)
			if anim_root:
				
				for anim_path_max_value_key in anim_path_maximums.keys():
				
					var object_to_animate : Node = anim_root.get_node(anim_path_max_value_key)
					if object_to_animate:
						object_to_animate.set(
							"blend_shapes/" + anim_path_max_value_key.get_subname(0),
							anim_path_maximums[anim_path_max_value_key])

func _process(delta: float) -> void:
	
	# Process sending of VMC data.
	if vmc_sender_enabled or vrc_sender_enabled:
		curr_client_send_time += delta
		if curr_client_send_time > client_send_rate_limit_ms / 1000:
			curr_client_send_time = 0
			if vmc_sender_enabled:
				_handle_vmc_sending()
			if vrc_sender_enabled:
				_handle_vrc_sending()
		
func _handle_vrc_sending() -> void:
	var model : Node3D = get_app().get_model()
	var skeleton : Skeleton3D = get_app().get_skeleton()
	var model_controller : ModelController = get_app().get_node("ModelController")
	var stack = []
	
	var blend_shapes = model_controller.get_blend_shape_values()
	if "eyeBlinkLeft" in blend_shapes:
		$KiriOSCClient.send_osc_message("/tracking/eye/EyesClosedAmount", "f", [blend_shapes["eyeBlinkLeft"]])
	
	for b in vrc_joint_names:
		var found = model_controller.find_mapped_bone_index(b)
		if found > -1:
			stack.append(found)
	
	while stack.size() > 0:
		var bone_index = stack.pop_back()
		var bone_name = skeleton.get_bone_name(bone_index)

		#var children = skeleton.get_bone_children(bone_index)
		#for child in children:
			#stack.append(child)
		

		var bone_trans = skeleton.get_bone_pose(bone_index)
		if bone_trans == null:
			continue
		
		var rot = bone_trans.basis.get_rotation_quaternion()
		
		var origin = Vector3(0.0, 0.0, 0.0)
		
		var scale_factor = 1.74 / 0.87
		
		var eul : Vector3 = bone_trans.basis.get_euler()
		
		if bone_name.to_lower() == "head":
			$KiriOSCClient.send_osc_message("/tracking/trackers/head/rotation", "fff", [
				eul.x * 100.0,
				eul.y * 100.0,
				eul.z * -1 * 100.0
			])
			#$KiriOSCClient.send_osc_message("/tracking/trackers/head/position", "fff", [
				#origin.x,
				#origin.y,
				#origin.z
			#])
		else:
			continue
		#bone_trans = skeleton.get_bone_rest(bone_index) * \
			#Transform3D(
				#skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion()).inverse() * \
			#Transform3D(
				#Basis(rot),
				#origin) * \
			#Transform3D(
				#skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion())
		#
		#rot = bone_trans.basis.get_rotation_quaternion()
				#
		#match bone_name.to_lower():
			#"rightupperarm":
				#rot = Quaternion(rot.z, -rot.y, rot.x, rot.w).normalized()
			##"leftupperarm":
				##rot = Quaternion(-rot.z, -rot.y, rot.x, rot.w).normalized()
			##_:
				##rot = Quaternion(rot.x, -rot.y, -rot.z, rot.w).normalized()
				#
		#bone_trans.basis = Basis(rot)
			#
		##var bone_parent = skeleton.get_bone_parent(bone_index)
		##if bone_parent > -1:
			##var parent_pose_global = skeleton.get_bone_global_pose(bone_parent)
			##var global_to_local = parent_pose_global * skeleton.get_bone_rest(bone_index)
			##bone_trans = global_to_local.affine_inverse() * bone_trans
		#
		#var trans: Vector3 = bone_trans.origin
		#var quat: Quaternion = bone_trans.basis.get_rotation_quaternion()
		#
		# Adjust for root.
		
			
		
	#
	#for key in blend_shapes.keys():
		#var val = blend_shapes[key]
		#var address = "/avatar/parameters/"
		#if key == "jawOpen":
			#address += "MouthOpen"
			## Inverse it for mouth open.
			##val = (val - 1) * -1
		#if key == "eyeBlinkLeft":
			#address += "Blink"
		#if key == "browDownLeft":
			#address += "BrowsDownUp"
		#if key == "mouthFunnel":
			#address += "MouthWideNarrow"
			#
		#if address == "/avatar/parameters/":
			#continue
		#
		##$KiriOSCClient.send_osc_message("/VMC/Ext/OK", "i", [1])
		#$KiriOSCClient.send_osc_message(address, "f", [val])
	
		
		
func _handle_vmc_sending() -> void:
	#print_log("Sending VMC Data")
	
	var model : Node3D = get_app().get_model()
	var skeleton : Skeleton3D = get_app().get_skeleton()
	var model_controller : ModelController = get_app().get_node("ModelController")
	
	# Send root transform
	# 2.1 introduced s and o.
	# /VMC/Ext/Root/Pos (string){name} (float){p.x} (float){p.y} (float){p.z} (float){q.x} (float){q.y} (float){q.z} (float){q.w} (float){s.x} (float){s.y} (float){s.z} (float){o.x} (float){o.y} (float){o.z}  
	# p=Position
	# q=Quaternion
	# s=MR Scale
	# o=MR Offset
	# Send bone transforms
	# /VMC/Ext/Bone/Pos (string){name} (float){p.x} (float){p.y} (float){p.z} (float){q.x} (float){q.y} (float){q.z} (float){q.w}  
	# p = position
	# q = quaternion
	var bundle_packet = _prepare_bone_hierarchy_bundle(model, skeleton, model_controller)
	$KiriOSCClient.send_osc_message_raw(bundle_packet)

	# Send blend values, THEN send blend apply.
	# /VMC/Ext/Blend/Val (string){name} (float){value}  
	# /VMC/Ext/Blend/Apply
	
	# Send camera transform & FOV
	# /VMC/Ext/Cam (string){name} (float){p.x} (float){p.y} (float){p.z} (float){q.x} (float){q.y} (float){q.z} (float){q.w} (float){fov} 
	
	# Send eye tracking target position
	# /VMC/Ext/Set/Eye (int){enable} (float){p.x} (float){p.y} (float){p.z}
	# v2.3-2.7 = ABSOLUTE position.
	# v2.8 = Head RELATIVE position.
	$KiriOSCClient.send_osc_message("/VMC/Ext/OK", "i", [1])
	$KiriOSCClient.send_osc_message("/VMC/Ext/T", "t", [_get_timetag_for_current_time()])
	
	
func _prepare_bone_hierarchy_bundle(model: Node3D, skeleton: Skeleton3D, model_controller: ModelController) -> PackedByteArray:
	#var bone_count = skeleton.get_bone_count()
	var stack = []
	var packets = []
	
	# Initialize the stack with all root bones (bones with no parent)
	#for i in range(bone_count):
		#if skeleton.get_bone_parent(i) == -1:
			#stack.append(i)  # (bone_index, indent_level)
	
	for b in joint_names:
		var found = model_controller.find_mapped_bone_index(b)
		if found > -1:
			stack.append(found)
	
	while stack.size() > 0:
		var bone_index = stack.pop_back()
		var bone_name = skeleton.get_bone_name(bone_index)

		var children = skeleton.get_bone_children(bone_index)
		for child in children:
			stack.append(child)
		
		var address = "/VMC/Ext/Bone/Pos"
		
		# Adjust for root.
		if bone_name.to_lower() == "root" || bone_name.to_lower() == "hips":
			address = "/VMC/Ext/Root/Pos"
			bone_name = "root"

		var packet_res = _prepare_vmc_packet_for_bone(address, bone_name, bone_index, model, skeleton, model_controller)
		if not packet_res[0]:
			pass
			#print("Cannot find bone: %s (idx: %d)", [bone_name, bone_index])
		else:
			packets.append(packet_res[1])
		
	# Return the prepared bundle.
	var timetag = _get_timetag_for_current_time()
	return $KiriOSCClient.create_osc_bundle(timetag, packets)
	
func _prepare_vmc_packet_for_bone(address: String,
									bone_name: String, bone_index: int,
									model: Node3D, skeleton: Skeleton3D,
									model_controller: ModelController) -> Array:
	if bone_name == "root":
		var pos = model.position
		var quat = model.transform.basis.get_rotation_quaternion()
		var scale = model.transform.basis.get_scale()
		return [
			true, 
			$KiriOSCClient.prepare_osc_message(address, "sfffffffffffff", 
			[
				bone_name, 
				# Unity works in flipped axis.
				pos.x, pos.y * -1.0, pos.z * -1.0,
				quat.x, quat.y * -1.0, quat.z * -1.0, quat.w,
				scale.x, scale.y, scale.z,
				0, 0, 0 # FIXME: Model root offset!
			])
		]
	else:
		var bone_trans = skeleton.get_bone_pose(bone_index)
		if bone_trans == null:
			return [false, null]
		
		var rot = bone_trans.basis.get_rotation_quaternion()
		
		var origin = Vector3(0.0, 0.0, 0.0)
		
		bone_trans = skeleton.get_bone_rest(bone_index) * \
			Transform3D(
				skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion()).inverse() * \
			Transform3D(
				Basis(rot),
				origin) * \
			Transform3D(
				skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion())
		
		rot = bone_trans.basis.get_rotation_quaternion()
				
		match bone_name.to_lower():
			"rightupperarm":
				rot = Quaternion(rot.z, -rot.y, rot.x, rot.w).normalized()
			#"leftupperarm":
				#rot = Quaternion(-rot.z, -rot.y, rot.x, rot.w).normalized()
			#_:
				#rot = Quaternion(rot.x, -rot.y, -rot.z, rot.w).normalized()
				
		bone_trans.basis = Basis(rot)
			
		#var bone_parent = skeleton.get_bone_parent(bone_index)
		#if bone_parent > -1:
			#var parent_pose_global = skeleton.get_bone_global_pose(bone_parent)
			#var global_to_local = parent_pose_global * skeleton.get_bone_rest(bone_index)
			#bone_trans = global_to_local.affine_inverse() * bone_trans
		
		var trans: Vector3 = bone_trans.origin
		var quat: Quaternion = bone_trans.basis.get_rotation_quaternion()
		return [
			true,
			$KiriOSCClient.prepare_osc_message(address, "sfffffff",
			[
				bone_name,
				trans.x, trans.y, trans.z,
				quat.x, quat.y, quat.z, quat.w
			])
		]



		
		#var q: Quaternion = bone_trans.basis.get_rotation_quaternion()
		##q.y *= -1.0
		##q.z *= -1.0
		#q = q.normalized()
		#
		#bone_trans = Transform3D(Basis(q), bone_trans.origin)
		#
		#var bone_parent = skeleton.get_bone_parent(bone_index)
		#if bone_parent > -1:
			#var parent_pose_global = skeleton.get_bone_global_pose(bone_parent)
			#var local_trans = parent_pose_global * skeleton.get_bone_rest(bone_index)
			#bone_trans = local_trans.affine_inverse() * bone_trans
			#
			
			
			
			
			
			
			
			
			
			
		#var bone_to_global = skeleton.global_transform * bone_trans
		#var axis_local = bone_to_global.basis.transposed()
		
		#bone_trans = Transform3D(axis_local, bone_trans.origin)
		#var bone_parent = skeleton.get_bone_parent(bone_index)
		#if bone_parent > -1:
			#var parent_pose_global = skeleton.get_bone_global_pose(bone_parent)
			#var global_to_local = parent_pose_global * skeleton.get_bone_rest(bone_index)
			#bone_trans = global_to_local.affine_inverse() * bone_trans
		
		#var q: Quaternion = bone_trans.basis.get_rotation_quaternion()
		#q.y *= -1.0
		#q.z *= -1.0
		#q = q.normalized()
		
		#bone_trans = Transform3D(Basis(q), bone_trans.origin)
		
		#bone_trans = skeleton.global_transform * bone_trans
		
		
		
		
		
		#var bone_trans = skeleton.get_bone_pose(bone_index)
		#if bone_trans == null:
			#return [false, null]
		#
		#var q: Quaternion = bone_trans.basis.get_rotation_quaternion()
		##q.y *= -1.0
		##q.z *= -1.0
		##q = q.normalized()
		#
		
		#var bone_parent = skeleton.get_bone_parent(bone_index)
		#if bone_parent > -1:
			#var parent_pose_global = skeleton.get_bone_global_pose(bone_parent)
			#var local_trans = parent_pose_global * skeleton.get_bone_rest(bone_index)
			#bone_trans = local_trans.affine_inverse() * bone_trans
			#
		
		
		
		
		
		
		
		
		
		
		
		#if bone_name != "RightShoulder":
			#return [false, null]
		
		#var trans_vec: Vector3 = bone_trans.origin
		#var quat: Quaternion = bone_trans.basis.get_rotation_quaternion()
		#quat.y *= -1.0
		#quat.z *= -1.0
		#quat = quat.normalized()
		
		#var T1 = skeleton.get_bone_rest(bone_index)
		#var T2 = Transform3D(skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion()).inverse()
		#var T3 = bone_trans
		#var T4 = Transform3D(skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion())

		# Now, calculate the inverse transformation
		#var new_transform : Transform3D = \
		#	T1.inverse() * \
		#	T2.inverse() * \
			#T3.inverse() * \
		#	T4.inverse()
		#var new_transform : Transform3D = \
				#skeleton.get_bone_rest(bone_index) * \
				#Transform3D(
					#skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion()) * \
				#Transform3D(
					#Basis(quat),
					#trans_vec) * \
				#Transform3D(
					#skeleton.get_bone_global_rest(bone_index).basis.get_rotation_quaternion()).inverse()
		
		#var bone_euler = bone_trans.basis.get_euler()
		#match bone_name.to_lower():
			#"leftupperarm":
				#bone_euler = Vector3(bone_euler.z, -bone_euler.y, bone_euler.x)
			#"rightupperarm":
				#bone_euler = Vector3(-bone_euler.z, -bone_euler.y, bone_euler.x)
			#_:
				#bone_euler = Vector3(bone_euler.x, -bone_euler.y, -bone_euler.z)
		#
		#var local_rest_pose = skeleton.get_bone_global_rest(bone_index)
		#var rest_euler = local_rest_pose.basis.get_euler()
		#
		#var new_rot = Quaternion.from_euler(rest_euler) * Quaternion.from_euler(bone_euler)
		#bone_trans = Transform3D(Basis(new_rot), bone_trans.origin)
		#
		#var new_trans_vec: Vector3 = Vector3(0.0, 0.0, 0.0) #bone_trans.origin
		#var new_quat: Quaternion = bone_trans.basis.get_rotation_quaternion()
		
		#if vmc_send_mirrored_arms:
			#if bone_name.begins_with("Left"):
				#print("Replacing %s with %s" % [bone_name, "Right"])
				#bone_name = bone_name.replace("Left", "Right")
			#elif bone_name.begins_with("Right"):
				#print("Replacing %s with %s" % [bone_name, "Left"])
				#bone_name = bone_name.replace("Right", "Left")

func _get_timetag_for_current_time() -> int:
	return Time.get_unix_time_from_system() - ntp_start_unix
