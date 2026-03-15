--- Lists available versions for a tool in this backend
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions
--- @param ctx BackendListVersionsCtx
--- @return BackendListVersionsResult
function PLUGIN:BackendListVersions(ctx)
	local tool = ctx.tool

	if not tool or tool == "" then
		error("Tool name cannot be empty")
	end

	local cmd = require("cmd")
	local http = require("http")
	local json = require("json")
	local strings = require("strings")

	local trdl_output = cmd.exec("trdl list")

	local repo_url = nil
	local lines = strings.split(trdl_output, "\n")
	for _, line in ipairs(lines) do
		line = strings.trim_space(line)
		if line ~= "" then
			local fields = {}
			for field in line:gmatch("%S+") do
				table.insert(fields, field)
			end

			if fields[1] == tool then
				repo_url = fields[2]
				break
			end
		end
	end

	if not repo_url then
		error("TUF repository '" .. tool .. "' not found in `trdl list` output")
	end

	local targets_url = repo_url .. "/targets.json"
	local resp = http.get({ url = targets_url })

	if resp.status_code ~= 200 then
		error(
			"Failed to fetch TUF targets from " .. targets_url .. ": HTTP " .. resp.status_code
		)
	end

	local data = json.decode(resp.body)

	if not data or not data.signed or not data.signed.targets then
		error("Invalid TUF targets metadata from " .. targets_url)
	end

	local semver = require("semver")

	local version_set = {}
	local versions = {}
	local channel_set = {}
	local channels = {}

	for target_path, _ in pairs(data.signed.targets) do
		if strings.has_prefix(target_path, "releases/") then
			local parts = strings.split(target_path, "/")
			if #parts >= 2 then
				local version = parts[2]
				if not version_set[version] then
					version_set[version] = true
					table.insert(versions, version)
				end
			end
		elseif strings.has_prefix(target_path, "channels/") then
			local parts = strings.split(target_path, "/")
			if #parts >= 3 then
				local channel = parts[3]
				if not channel_set[channel] then
					channel_set[channel] = true
					table.insert(channels, channel)
				end
			end
		end
	end

	if #versions == 0 and #channels == 0 then
		error("No versions found for " .. tool .. " in TUF repository at " .. repo_url)
	end

	versions = semver.sort(versions)

	table.sort(channels)
	for _, channel in ipairs(channels) do
		table.insert(versions, channel)
	end

	return { versions = versions }
end
