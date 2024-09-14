--Joking the future is now! (Olddorito out. (100))
		-- place the VR head at the subject's CFrame
		newCameraCFrame = subjectCFrame
	else
		-- keep character rotation with torso
		local torsoRotation = self.controlModule:GetEstimatedVRTorsoFrame()
		self.characterOrientation.CFrame = curCamera.CFrame * torsoRotation 

		-- The character continues moving for a brief moment after the moveVector stops. Continue updating the camera.
		if self.controlModule.inputMoveVector.Magnitude > 0 then
			self.motionDetTime = 0.1
		end

		if self.controlModule.inputMoveVector.Magnitude > 0 or self.motionDetTime > 0 then
			self.motionDetTime -= timeDelta

			-- Add an edge blur if the subject moved
			self:StartVREdgeBlur(PlayersService.LocalPlayer)
			
			-- moving by input, so we should align the vrHead with the character
			local vrHeadOffset = VRService:GetUserCFrame(Enum.UserCFrame.Head) 
			vrHeadOffset = vrHeadOffset.Rotation + vrHeadOffset.Position * curCamera.HeadScale
			
			-- the location of the character's body should be "below" the head. Directly below if the player is looking 
			-- forward, but further back if they are looking down
			local hrp = character.HumanoidRootPart
			local neck_offset = NECK_OFFSET * hrp.Size.Y / 2
			local neckWorld = curCamera.CFrame * vrHeadOffset * CFrame.new(0, neck_offset, 0)
			local hrpLook = hrp.CFrame.LookVector
			neckWorld -= Vector3.new(hrpLook.X, 0, hrpLook.Z).Unit * hrp.Size.Y * TORSO_FORWARD_OFFSET_RATIO
			
			-- the camera must remain stable relative to the humanoid root part or the IK calculations will look jittery
			local goalCameraPosition = subjectPosition - neckWorld.Position + curCamera.CFrame.Position

			-- maintain the Y value
			goalCameraPosition = Vector3.new(goalCameraPosition.X, subjectPosition.Y, goalCameraPosition.Z)
			
			newCameraCFrame = curCamera.CFrame.Rotation + goalCameraPosition
		else
			-- don't change x, z position, follow the y value
			newCameraCFrame = curCamera.CFrame.Rotation + Vector3.new(curCamera.CFrame.Position.X, subjectPosition.Y, curCamera.CFrame.Position.Z)
		end
		
		local yawDelta = self:getRotation(timeDelta)
		if math.abs(yawDelta) > 0 then
			-- The head location in world space
			local vrHeadOffset = VRService:GetUserCFrame(Enum.UserCFrame.Head) 
			vrHeadOffset = vrHeadOffset.Rotation + vrHeadOffset.Position * curCamera.HeadScale
			local VRheadWorld = newCameraCFrame * vrHeadOffset

			local desiredVRHeadCFrame = CFrame.new(VRheadWorld.Position) * CFrame.Angles(0, -math.rad(yawDelta * 90), 0) * VRheadWorld.Rotation

			-- set the camera to place the VR head at the correct location
			newCameraCFrame = desiredVRHeadCFrame * vrHeadOffset:Inverse()
		end
	end

	return newCameraCFrame, newCameraCFrame * CFrame.new(0, 0, -FP_ZOOM)
end

function VRCamera:UpdateThirdPersonComfortTransform(timeDelta, newCameraCFrame, newCameraFocus, lastSubjPos, subjectPosition)
	local zoom = self:GetCameraToSubjectDistance()
	if zoom < 0.5 then
		zoom = 0.5
	end

	if lastSubjPos ~= nil and self.lastCameraFocus ~= nil then
		-- compute delta of subject since last update
		local player = PlayersService.LocalPlayer
		local subjectDelta = lastSubjPos - subjectPosition
		local moveVector
		if FFlagUserVRAvatarGestures then
			self.controlModule:GetMoveVector()
		else
			moveVector = require(player:WaitForChild("PlayerScripts").PlayerModule:WaitForChild("ControlModule")):GetMoveVector()
		end

		-- is the subject still moving?
		local isMoving = subjectDelta.magnitude > 0.01 or moveVector.magnitude > 0.01
		if isMoving then
			self.motionDetTime = 0.1
		end

		self.motionDetTime = self.motionDetTime - timeDelta
		if self.motionDetTime > 0 then
			isMoving = true
		end

		if isMoving and not self.needsReset then
			-- if subject moves keep old camera focus
			newCameraFocus = self.lastCameraFocus

			-- if the focus subject stopped, time to reset the camera
			self.VRCameraFocusFrozen = true
		else
			local subjectMoved = self.lastCameraResetPosition == nil or (subjectPosition - self.lastCameraResetPosition).Magnitude > 1

			-- compute offset for 3rd person camera rotation
			local yawDelta = self:getRotation(timeDelta)
			if math.abs(yawDelta) > 0 then
				local cameraOffset = newCameraFocus:ToObjectSpace(newCameraCFrame)
				newCameraCFrame = newCameraFocus * CFrame.Angles(0, -yawDelta, 0) * cameraOffset
			end

			-- recenter the camera on teleport
			if (self.VRCameraFocusFrozen and subjectMoved) or self.needsReset then
				VRService:RecenterUserHeadCFrame()

				self.VRCameraFocusFrozen = false
				self.needsReset = false
				self.lastCameraResetPosition = subjectPosition

				self:ResetZoom()
				self:StartFadeFromBlack()

				-- get player facing direction
				local humanoid = self:GetHumanoid()
				local forwardVector = humanoid.Torso and humanoid.Torso.CFrame.lookVector or Vector3.new(1,0,0)
				-- adjust camera height
				local vecToCameraAtHeight = Vector3.new(forwardVector.X, 0, forwardVector.Z)
				local newCameraPos = newCameraFocus.Position - vecToCameraAtHeight * zoom
				-- compute new cframe at height level to subject
				local lookAtPos = Vector3.new(newCameraFocus.Position.X, newCameraPos.Y, newCameraFocus.Position.Z)

				newCameraCFrame = CFrame.new(newCameraPos, lookAtPos)
			end
		end
	end

	return newCameraCFrame, newCameraFocus
end

function VRCamera:UpdateThirdPersonFollowTransform(timeDelta, newCameraCFrame, newCameraFocus, lastSubjPos, subjectPosition)
	local camera = workspace.CurrentCamera :: Camera
	local zoom = self:GetCameraToSubjectDistance()
	local vrFocus = self:GetVRFocus(subjectPosition, timeDelta)

	if self.needsReset then

		self.needsReset = false

		VRService:RecenterUserHeadCFrame()
		self:ResetZoom()
		self:StartFadeFromBlack()
	end
	
	if self.recentered then
		local subjectCFrame = self:GetSubjectCFrame()
		if not subjectCFrame then -- can't perform a reset until the subject is valid
			return camera.CFrame, camera.Focus
		end
		
		-- set the camera and focus to zoom distance behind the subject
		newCameraCFrame = vrFocus * subjectCFrame.Rotation * CFrame.new(0, 0, zoom)

		self.focusOffset = vrFocus:ToObjectSpace(newCameraCFrame) -- GetVRFocus returns a CFrame with no rotation
		
		self.recentered = false
		return newCameraCFrame, vrFocus
	end

	local trackCameraCFrame = vrFocus:ToWorldSpace(self.focusOffset)
	
	-- figure out if the player is moving
	local player = PlayersService.LocalPlayer
	local subjectDelta = lastSubjPos - subjectPosition
	local controlModule
	if FFlagUserVRAvatarGestures then
		controlModule = self.controlModule
	else
		controlModule = require(player:WaitForChild("PlayerScripts").PlayerModule:WaitForChild("ControlModule"))
	end
	local moveVector = controlModule:GetMoveVector()

	-- while moving, slowly adjust camera so the avatar is in front of your head
	if subjectDelta.magnitude > 0.01 or moveVector.magnitude > 0 then -- is the subject moving?

		local headOffset = controlModule:GetEstimatedVRTorsoFrame()

		-- account for headscale
		headOffset = headOffset.Rotation + headOffset.Position * camera.HeadScale
		local headCframe = camera.CFrame * headOffset
		local headLook = headCframe.LookVector

		local headVectorDirection = Vector3.new(headLook.X, 0, headLook.Z).Unit * zoom
		local goalHeadPosition = vrFocus.Position - headVectorDirection
		
		-- place the camera at currentposition + difference between goalHead and currentHead 
		local moveGoalCameraCFrame = CFrame.new(camera.CFrame.Position + goalHeadPosition - headCframe.Position) * trackCameraCFrame.Rotation 

		newCameraCFrame = trackCameraCFrame:Lerp(moveGoalCameraCFrame, 0.01)
	else
		newCameraCFrame = trackCameraCFrame
	end

	-- compute offset for 3rd person camera rotation
	local yawDelta = self:getRotation(timeDelta)
	if math.abs(yawDelta) > 0 then
		local cameraOffset = vrFocus:ToObjectSpace(newCameraCFrame)
		newCameraCFrame = vrFocus * CFrame.Angles(0, -yawDelta, 0) * cameraOffset
	end

	self.focusOffset = vrFocus:ToObjectSpace(newCameraCFrame) -- GetVRFocus returns a CFrame with no rotation

	-- focus is always in front of the camera
	newCameraFocus = newCameraCFrame * CFrame.new(0, 0, -zoom)

	-- vignette
	if (newCameraFocus.Position - camera.Focus.Position).Magnitude > 0.01 then
		self:StartVREdgeBlur(PlayersService.LocalPlayer)
	end

	return newCameraCFrame, newCameraFocus
end

function VRCamera:LeaveFirstPerson()
	VRBaseCamera.LeaveFirstPerson(self)
	
	self.needsReset = true
	if self.VRBlur then
		self.VRBlur.Visible = false
	end

	if FFlagUserVRAvatarGestures then
		if self.characterOrientation then
			self.characterOrientation.Enabled = false

		end
		local humanoid = self:GetHumanoid()
		if humanoid then
			humanoid.AutoRotate = self.savedAutoRotate
		end
	end
end

return VRCamera
end))
----------

	-- Advance the spring simulation by `dt` seconds
	function Spring:step(dt: number)
		local f: number = self.freq::number * 2.0 * math.pi
		local g: Vector3 = self.goal
		local p0: Vector3 = self.pos
		local v0: Vector3 = self.vel

		local offset = p0 - g
		local decay = math.exp(-f*dt)

		local p1 = (offset*(1 + f*dt) + v0*dt)*decay + g
		local v1 = (v0*(1 - f*dt) - offset*(f*f*dt))*decay

		self.pos = p1
		self.vel = v1

		return p1
	end
end
------------- this part probably has nothing related with vr cameras
