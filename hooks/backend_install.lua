--- @param repo_url string
--- @param channel string
--- @param http http
--- @param json json
--- @param strings strings
--- @return string
local function resolve_channel(repo_url, channel, http, json, strings)
	local targets_url = repo_url .. "/targets.json"
	local resp = http.get({ url = targets_url })

	if resp.status_code ~= 200 then
		error("Failed to fetch TUF targets from " .. targets_url .. ": HTTP " .. resp.status_code)
	end

	local data = json.decode(resp.body)
	if not data or not data.signed or not data.signed.targets then
		error("Invalid TUF targets metadata from " .. targets_url)
	end

	local best_group = nil
	for target_path, _ in pairs(data.signed.targets) do
		if strings.has_prefix(target_path, "channels/") then
			local parts = strings.split(target_path, "/")
			if #parts >= 3 and parts[3] == channel then
				local group = parts[2]
				if not best_group or group > best_group then
					best_group = group
				end
			end
		end
	end

	if not best_group then
		error("Channel '" .. channel .. "' not found in TUF repository")
	end

	local channel_url = repo_url .. "/targets/channels/" .. best_group .. "/" .. channel
	local channel_resp = http.get({ url = channel_url })

	if channel_resp.status_code ~= 200 then
		error("Failed to fetch channel '" .. channel .. "': HTTP " .. channel_resp.status_code)
	end

	local resolved = strings.trim_space(channel_resp.body)
	if resolved == "" then
		error("Channel '" .. channel .. "' resolved to empty version")
	end

	return resolved
end

--- Installs a specific version of a tool
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendinstall
--- @param ctx BackendInstallCtx
--- @return BackendInstallResult
function PLUGIN:BackendInstall(ctx)
	local tool = ctx.tool
	local version = ctx.version
	local install_path = ctx.install_path

	if not tool or tool == "" then
		error("Tool name cannot be empty")
	end
	if not version or version == "" then
		error("Version cannot be empty")
	end
	if not install_path or install_path == "" then
		error("Install path cannot be empty")
	end

	local cmd = require("cmd")
	local http = require("http")
	local json = require("json")
	local file = require("file")
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

	local resolved_version = version

	if not version:match("^%d") then
		resolved_version = resolve_channel(repo_url, version, http, json, strings)
	end

	local platform = RUNTIME.osType:lower()
	local arch = RUNTIME.archType
	local binary_name = tool
	if platform == "windows" then
		binary_name = tool .. ".exe"
	end

	local target_path = "releases/"
		.. resolved_version
		.. "/"
		.. platform
		.. "-"
		.. arch
		.. "/bin/"
		.. binary_name
	local download_url = repo_url .. "/targets/" .. target_path

	local bin_dir = file.join_path(install_path, "bin")
	cmd.exec("mkdir -p " .. bin_dir)

	local dest_path = file.join_path(bin_dir, binary_name)
	http.download_file({ url = download_url }, dest_path)

	if platform ~= "windows" then
		cmd.exec("chmod +x " .. dest_path)
	end

	return {}
end
