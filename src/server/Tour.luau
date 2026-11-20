-- Tour.luau
-- ModuleScript invoked by the make.fun tour runner to drive scripted demo beats
-- (tsunami disaster, cash grant, bag bank) during automated screenshot capture.

local Tour = {}

Tour.hooks = {}

function Tour.tsunami(arg)
	local handler = Tour.hooks["tsunami"]
	if handler then
		return handler(arg)
	end
	warn("[Tour] no 'tsunami' hook registered; arg =", arg)
end

function Tour.cash(arg)
	local handler = Tour.hooks["cash"]
	if handler then
		return handler(arg)
	end
	warn("[Tour] no 'cash' hook registered; arg =", arg)
end

function Tour.bank(arg)
	local handler = Tour.hooks["bank"]
	if handler then
		return handler(arg)
	end
	warn("[Tour] no 'bank' hook registered; arg =", arg)
end

return Tour
