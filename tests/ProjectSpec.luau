--!strict
-- Prueft, dass test.project.json (Test-Place) zum normalen Projekt passt: gleiche Skript-
-- Ordner und alle RemoteEvents. Sonst fehlt im Test-Place z. B. ein neues RemoteEvent.
-- Neu erzeugen: lune run tools/build_testplace
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local TestLib = require("./TestLib")

local describe, it, expect = TestLib.describe, TestLib.it, TestLib.expect

describe("Test-Place-Projekt", function()
	local main = serde.decode("json", fs.readFile("default.project.json"))
	local test = serde.decode("json", fs.readFile("test.project.json"))

	it("hat alle RemoteEvents des normalen Projekts", function()
		for name in main.tree.ReplicatedStorage.Remotes do
			if string.sub(name, 1, 1) ~= "$" then
				expect(test.tree.ReplicatedStorage.Remotes[name] ~= nil).toBe(true)
			end
		end
	end)

	it("nutzt dieselben Skript-Ordner (Live-Sync mit rojo serve)", function()
		expect(test.tree.ReplicatedStorage.Shared["$path"]).toBe(main.tree.ReplicatedStorage.Shared["$path"])
		expect(test.tree.ServerScriptService.Server["$path"]).toBe(
			main.tree.ServerScriptService.Server["$path"]
		)
		expect(test.tree.StarterPlayer.StarterPlayerScripts.Client["$path"]).toBe(
			main.tree.StarterPlayer.StarterPlayerScripts.Client["$path"]
		)
	end)

	it("enthaelt Teststrecke, Testflaeche und Vorlagen", function()
		expect(test.tree.Workspace.TestTrack ~= nil).toBe(true)
		expect(test.tree.Workspace.Testflaeche ~= nil).toBe(true)
		expect(test.tree.ReplicatedStorage.Templates ~= nil).toBe(true)
		expect(fs.isFile("test/TestTrack.rbxm")).toBe(true)
		expect(fs.isFile("test/Templates.rbxm")).toBe(true)
	end)
end)

return nil
