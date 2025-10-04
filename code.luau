--[[MIT License

Copyright (c) 2025 BerserkerStudios

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]

--placed in ReplicatedStorage and ran by a module loader(ssa)
--Module.Init runs --> Module.Start runs after

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local UserInputService = game:GetService("UserInputService")

local Networker = require(ReplicatedStorage.Packages.Networker) --lovely remote event replacement by LeifIsOut

local player = Players.LocalPlayer

local VISUALIZE_HITBOX = true --using SCREAMING_SNAKE_CASE on this one since its a constant

local networker
local holdingM1 = false
local canAttack = true
local combo = 1
local resetCombo
local blockAnim
local blocking = false

local Combat = {}

function Combat:HitFX(enemy) --using : because of Networker, the server side spawns the hitFX on all clients(except this one)
	local highlight = Instance.new("Highlight") --you can only have 21 of these
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded --makes it so you cant see the highlight trough instances
	highlight.FillColor = Color3.new(1, 0.160784, 0.160784) --color3.new is like fromRGB except it goes from 0 to 1
	highlight.Parent = enemy

	task.delay(0.2, highlight.Destroy, highlight) --Destroy uses : so we need to pass in self

	local hitFx = ReplicatedStorage.HitFX.Attachment:Clone()
	hitFx.Parent = enemy.HumanoidRootPart
	--particles need to be emitted after parenting to world root otherwise it wont work
	for _, v in hitFx:GetChildren() do
		v:Emit(v:GetAttribute("EmitCount"))
	end
end

function Combat.Attack()
	if blocking then
		return
	end
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid") --the controller instance of all characters
	if not humanoid then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") --every character has this
	if not hrp then
		return
	end

	canAttack = false

	networker:fire("Attack") --fire as soon as possible

	local animation = ReplicatedStorage.Animations.Attacks[combo] --indexing an instance auto converts combo(number) into a string
	local anim = humanoid.Animator:LoadAnimation(animation)
	anim:Play()

	anim:GetMarkerReachedSignal("Hitbox")
		:Once(function() --Once is like Connect but only runs once so its perfect for this situation
			if combo == 4 then
				local attachment = Instance.new("Attachment")
				local linearVelocity = Instance.new("LinearVelocity") --replacement for the depracated BodyVelocity
				linearVelocity.Attachment0 = attachment
				linearVelocity.MaxForce = 10000 --make sure to set maxForce to a finite amount so it wont randomly fling the character
				linearVelocity.VectorVelocity = (hrp.CFrame * CFrame.new(0, 0, -150)).Position --doing it with CFrames and then getting the position so its relative to the character
				linearVelocity.Parent = attachment
				attachment.Parent = hrp
				task.delay(0.2, attachment.Destroy, attachment)
			end

			local size = Vector3.new(4, 4, 4)
			local cframe = hrp.CFrame * CFrame.new(0, 0, -size.Z / 2) --cframes are like vectors but with orientation

			local visualizer --undefined variable, not the same as nil
			if VISUALIZE_HITBOX then
				visualizer = Instance.new("Part")
				visualizer.Massless = true --important since were welding it to the character, if it wasnt set to true it would make the character feel heavy or have other weird physics
				visualizer.CastShadow = false
				visualizer.CanCollide = false --it wont collide with anything
				visualizer.Transparency = 0.5
				visualizer.Color = Color3.fromRGB(255, 0, 0) --rgb has 3 values that range from 0 to 255

				visualizer.CFrame = cframe
				visualizer.Size = size

				local weld = Instance.new("WeldConstraint")
				weld.Parent = visualizer --we dont have to parent last since were parenting it to an instance which doesnt have the parent set to a world root
				weld.Part0 = visualizer
				weld.Part1 = hrp

				visualizer.Parent = workspace --parenting it last to save performance
				task.delay(0.2, visualizer.Destroy, visualizer)
			end

			local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Exclude --i hate how its Enum.RaycastFilterType for OverlapParams
			overlapParams.FilterDescendantsInstances = { character } --will exclude every descendant of character from the query we later use

			local hitHumanoids = {}

			local parts = workspace:GetPartBoundsInBox(cframe, size, overlapParams)
			for _, part in parts do
				local enemy = part:FindFirstAncestorOfClass("Model") --ancestor means every instance that is higher then the part in the object hierarchy
				if not enemy then --ffaoc will return false if it doesnt find it so we can do if not
					continue --skip to the next member of the loop
				end

				local enemyHumanoid = enemy:FindFirstChild("Humanoid")
				if not enemyHumanoid then
					continue
				end

				if enemyHumanoid.Health <= 0 then
					continue
				end

				if not enemy:FindFirstChild("HumanoidRootPart") then
					continue
				end

				if table.find(hitHumanoids, enemyHumanoid) then --if it already is in the table
					continue
				end
				table.insert(hitHumanoids, enemyHumanoid) --adding it to the table

				Combat:HitFX(enemy)
			end

			if #hitHumanoids > 0 then --if the number of elements in the table is greater then zero
				networker:fire("Hit", hitHumanoids)
			end
			table.clear(hitHumanoids) --makes it an empty table
		end)

	anim.Ended:Wait() --waits untill the .Ended signal fires

	if combo >= 4 then
		task.wait(1)
	end

	if combo < 4 then
		combo += 1 --this is the same as combo = combo + 1
	else
		combo = 1
	end
	if resetCombo then --some simple error protection
		task.cancel(resetCombo) --cancels the delay meaning it wont run
	end
	resetCombo = task.delay(4, function() --basically task.wait(4) task.defer(function() end)
		combo = 1
	end)

	canAttack = true
end

function Combat.StartAttacking()
	while holdingM1 and task.wait() do --will run on every heartbeat(task.wait) untill holdingM1 is false or nil
		if not player.Character then --if the players character hasnt loaded in yet, we need character for function "attack"
			continue
		end

		if not canAttack then --if its false or nil
			continue --stops the code bellow from running (return but for loops)
		end

		Combat.Attack()
	end
end

function Combat.StartBlocking()
	if holdingM1 then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	blocking = true
	humanoid.WalkSpeed = 10

	if not blockAnim then --we only load it once
		blockAnim = humanoid.Animator:LoadAnimation(ReplicatedStorage.Animations.Block)
	end

	blockAnim:Play()
end

function Combat.StopBlocking()
	blocking = false

	local humanoid = if player.Character then player.Character:FindFirstChild("Humanoid") else false --if there is a character then we will search for a humanoid, if there isnt a character or there isnt a humanoid inside the character then we set the variable to false
	if humanoid then
		humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed --with StarterPlayer were making sure the walkspeed gets set to the one we have as default
	end

	if blockAnim then
		blockAnim:Stop()
	end
end

function Combat.Init()
	networker = Networker.client.new("Combat", Combat)
end

function Combat.Start()
	UserInputService.InputBegan:Connect(
		function(input, processed) --beginning input means for example to start pressing down a key
			if processed then --if typing in chat or roblox menu opened etc.
				return --stops the rest of the code in this function from running
			end

			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				holdingM1 = true
				Combat.StartAttacking() --runs all the code inside of the function startAttacking (calls the function)
			elseif input.KeyCode == Enum.KeyCode.F then --for keys on the keyboard we use KeyCode instead of UserInputType
				Combat.StartBlocking()
			end
		end
	)

	UserInputService.InputEnded:Connect(function(input) --ending input means for example to stop pressing down a key
		--dont use processed here since it would be super janky if you started attacking and then opened menu and let go of m1 and it would still continue attacking
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdingM1 = false
		elseif input.KeyCode == Enum.KeyCode.F then --for keys on the keyboard we use KeyCode instead of UserInputType
			Combat.StopBlocking()
		end
	end)
end

return Combat
