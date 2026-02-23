-- Re-exports the shared Signal so UILibrary modules have one canonical implementation.
return require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Shared")
		:WaitForChild("Util")
		:WaitForChild("Signal")
)
