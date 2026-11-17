-- Tour hooks: ServerScriptService.Server.Tour
-- Reviewers (and TOUR.json) can call these functions on the Server to bring the game to a given screen.
-- The main server script fills in Tour.hooks when it starts; require() caches this table, so the
-- tour runner and the game share the same hooks.

local Tour = {}

Tour.hooks = {} :: { [string]: (any) -> () }

local function run(name: string, arg: any)
	local hook = Tour.hooks[name]
	if hook then
		hook(arg)
	else
		warn("[Tour] hook not ready: " .. name)
	end
end

-- Start the tsunami warning right now (arg ignored).
function Tour.tsunami(arg: any)
	run("tsunami", arg)
end

-- Give every player `arg` cash (an integer).
function Tour.cash(arg: any)
	run("cash", tonumber(arg) or 1000)
end

-- Bank `arg` random brainrots onto every player's base (an integer).
function Tour.bank(arg: any)
	run("bank", tonumber(arg) or 5)
end

return Tour
