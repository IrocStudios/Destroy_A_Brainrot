local Janitor = {}
Janitor.__index = Janitor

function Janitor.new()
	return setmetatable({ _tasks = {} }, Janitor)
end

function Janitor:Add(task, method)
	table.insert(self._tasks, { task = task, method = method })
	return task
end

function Janitor:Cleanup()
	for i = #self._tasks, 1, -1 do
		local item = self._tasks[i]
		local t, m = item.task, item.method
		if typeof(t) == "RBXScriptConnection" then
			t:Disconnect()
		elseif typeof(t) == "Instance" then
			t:Destroy()
		elseif typeof(t) == "function" then
			t()
		elseif m and t and t[m] then
			t[m](t)
		end
		self._tasks[i] = nil
	end
end

Janitor.Destroy = Janitor.Cleanup
Janitor.Clean   = Janitor.Cleanup -- alias used by UILibrary consumers
return Janitor
