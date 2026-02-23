-- Re-exports Janitor as the canonical cleaner.
-- Janitor exposes: Add(task, method?), Cleanup(), Clean() (alias), Destroy() (alias).
return require(
	game:GetService("ReplicatedStorage")
		:WaitForChild("Shared")
		:WaitForChild("Util")
		:WaitForChild("Janitor")
)
