-- sync.lua — multi-machine sync of LuaTools state (git or folder backend).
--
-- Faithful Lua port of sync_engine.py. Explicit push/pull, no silent overwrites.
-- Git backend shells to the `git` CLI; folder backend copies files. Config
-- get/set are plain JSON. File comparison uses size (Lua has no sha256), and
-- conflict detection uses size+mtime (Python used sha256 -- behaviourally close
-- for the "skip identical / don't clobber newer local" contract).
--
-- On-machine-verified for git/folder ops (shells to git; not harness-testable).

local cjson       = require("json")
local m_utils     = require("utils")
local fs          = require("fs")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

-- (logical_name, data-file name, optional)
local SYNC_ITEMS = {
    { "key_vault.json", "key_vault.json", false },
    { "sentinel_config.json", "sentinel_config.json", true },
    { "sentinel_state.json", "sentinel_state.json", true },
    { "custom_apis.json", "custom_apis.json", true },
    { "source_chain.json", "source_chain.json", true },
}

local function config_path() return st.data_path("sync_config.json") end

local function default_config()
    return {
        backend = "git",
        git = { remote_url = "", branch = "main", auto_pull_on_start = false,
                auto_push_on_change = false, include_history_db = false, include_lua_scripts = true },
        folder = { path = "", include_history_db = false, include_lua_scripts = true },
        last_push = 0, last_pull = 0,
    }
end

local function read_config()
    local p = config_path()
    if not fs.is_file(p) then return default_config() end
    local ok, data = pcall(cjson.decode, m_utils.read_file(p) or "")
    if ok and type(data) == "table" then return data end
    logger.warn("sync: failed reading config")
    return {}
end

local function write_config(cfg)
    return m_utils.write_file(config_path(), cjson.encode(cfg)) ~= false
end

local function sync_root()
    local root = st.data_path("sync_repo")
    if not fs.exists(root) then pcall(fs.create_directories, root) end
    return root
end

local function stplug_dir() return st.stplug_dir() end

local function collect_lua_scripts()
    local stplug = stplug_dir()
    local out = {}
    if stplug == "" or not fs.is_directory(stplug) then return out end
    for _, e in ipairs(fs.list(stplug) or {}) do
        local n = e.name or ""
        if (n:match("%.lua$") or n:match("%.lua%.disabled$")) and e.is_file then
            table.insert(out, { "stplug-in/" .. n, e.path })
        end
    end
    return out
end

local function collect_data_files(include_history)
    local out = {}
    for _, item in ipairs(SYNC_ITEMS) do
        local src = st.data_path(item[2])
        if fs.is_file(src) then table.insert(out, { "data/" .. item[1], src }) end
    end
    if include_history then
        local hist = st.data_path("download_history.json")
        if fs.is_file(hist) then table.insert(out, { "data/download_history.json", hist }) end
    end
    return out
end

local function build_manifest(files)
    local entries = {}
    for _, f in ipairs(files) do
        table.insert(entries, {
            path = f[1], sha256 = "",
            size = fs.file_size(f[2]) or 0, mtime = fs.last_write_time(f[2]) or 0,
        })
    end
    return { version = "1.0", created_at = math.floor(m_utils.time()),
             machine = m_utils.getenv("COMPUTERNAME") or "unknown", files = st.A(entries) }
end

local function same_size(a, b)
    return fs.is_file(a) and fs.is_file(b) and (fs.file_size(a) == fs.file_size(b))
end

local function stage_files(files)
    local root = sync_root()
    local copied, skipped, errors = 0, 0, {}
    for _, f in ipairs(files) do
        local rel, src = f[1], f[2]
        local dest = fs.join(root, rel)
        pcall(fs.create_directories, fs.parent_path(dest))
        if same_size(src, dest) then
            skipped = skipped + 1
        elseif fs.copy(src, dest) then
            copied = copied + 1
        else
            table.insert(errors, "copy " .. rel)
        end
    end
    m_utils.write_file(fs.join(root, "manifest.json"), cjson.encode(build_manifest(files)))
    return { copied = copied, skipped = skipped, errors = st.A(errors) }
end

local function apply_pulled_files(dry_run)
    local root = sync_root()
    if not fs.is_directory(root) then return { success = false, error = "sync_repo missing - pull first" } end
    local mp = fs.join(root, "manifest.json")
    if not fs.is_file(mp) then return { success = false, error = "manifest.json missing in pulled data" } end
    local ok, manifest = pcall(cjson.decode, m_utils.read_file(mp) or "")
    if not ok or type(manifest) ~= "table" then return { success = false, error = "invalid manifest" } end

    local stplug = stplug_dir()
    local applied, skipped, conflicts, errors = {}, {}, {}, {}
    for _, entry in ipairs(manifest.files or {}) do
        local rel = entry.path or ""
        local src = fs.join(root, rel)
        if rel ~= "" and fs.is_file(src) then
            local dst
            if rel:sub(1, 5) == "data/" then
                dst = st.data_path(rel:sub(6))
            elseif rel:sub(1, 10) == "stplug-in/" and stplug ~= "" then
                dst = fs.join(stplug, rel:sub(11))
            end
            if dst then
                local do_apply = true
                if fs.is_file(dst) then
                    if same_size(dst, src) then
                        table.insert(skipped, { path = rel, reason = "identical" }); do_apply = false
                    else
                        local local_mtime = fs.last_write_time(dst) or 0
                        if local_mtime > (entry.mtime or 0) then
                            table.insert(conflicts, { path = rel, local_mtime = local_mtime, remote_mtime = entry.mtime or 0 })
                            do_apply = false
                        end
                    end
                end
                if do_apply then
                    if dry_run then
                        table.insert(applied, { path = rel, would_apply = true })
                    else
                        if fs.is_file(dst) then m_utils.write_file(dst .. ".presync-" .. st.stamp(), m_utils.read_file(dst) or "") end
                        pcall(fs.create_directories, fs.parent_path(dst))
                        if fs.copy(src, dst) then table.insert(applied, { path = rel }) else table.insert(errors, "apply " .. rel) end
                    end
                end
            else
                table.insert(errors, "unknown path category: " .. rel)
            end
        elseif rel ~= "" then
            table.insert(errors, "missing in pulled data: " .. rel)
        end
    end
    return {
        success = true, applied = st.A(applied), skipped = st.A(skipped),
        conflicts = st.A(conflicts), errors = st.A(errors), dry_run = dry_run == true,
    }
end

-- ── git backend ──────────────────────────────────────────────────────────────

local function run_git(args_str, root, _timeout)
    local out, code = m_utils.exec('git -C "' .. root .. '" ' .. args_str .. ' 2>&1')
    if type(code) ~= "number" then code = (out and out ~= "") and 0 or -1 end
    return code, tostring(out or "")
end

local function git_init_or_pull(remote_url, branch)
    local root = sync_root()
    if not fs.is_directory(fs.join(root, ".git")) then
        local code, err = run_git("init", root)
        if code ~= 0 then return { success = false, error = "git init: " .. err } end
        code, err = run_git('remote add origin "' .. remote_url .. '"', root)
        if code ~= 0 and not err:find("already exists", 1, true) then
            return { success = false, error = "git remote add: " .. err }
        end
        code, err = run_git("fetch origin " .. branch, root)
        if code ~= 0 then return { success = false, error = "git fetch: " .. err } end
        run_git("checkout -B " .. branch .. " origin/" .. branch, root)
    else
        local code, err = run_git("pull --ff-only origin " .. branch, root)
        if code ~= 0 then return { success = false, error = "git pull: " .. err } end
    end
    return { success = true }
end

local function git_push(branch, message)
    local root = sync_root()
    if not fs.is_directory(fs.join(root, ".git")) then return { success = false, error = "not a git repo - run pull first" } end
    run_git("add -A", root)
    local code, out = run_git('commit -m "' .. message .. '"', root)
    if code ~= 0 and not out:lower():find("nothing to commit", 1, true) then
        return { success = false, error = "git commit: " .. out }
    end
    code, out = run_git("push origin " .. branch, root)
    if code ~= 0 then return { success = false, error = "git push: " .. out } end
    return { success = true, output = out }
end

-- ── folder backend ─────────────────────────────────────────────────────────

local function folder_push(folder_path)
    if not folder_path or folder_path == "" then return { success = false, error = "folder path empty" } end
    pcall(fs.create_directories, folder_path)
    local root = sync_root()
    if not fs.is_directory(root) then return { success = false, error = "sync_repo missing" } end
    local copied = 0
    for _, e in ipairs(fs.list_recursive(root) or {}) do
        if e.is_file and not e.path:find("\\.git\\", 1, true) and not e.path:find("/.git/", 1, true) then
            local rel = e.path:sub(#root + 1):gsub("^[/\\]+", "")
            local dst = fs.join(folder_path, rel)
            if not same_size(e.path, dst) then
                pcall(fs.create_directories, fs.parent_path(dst))
                if fs.copy(e.path, dst) then copied = copied + 1 end
            end
        end
    end
    return { success = true, copied = copied }
end

local function folder_pull(folder_path)
    if not folder_path or folder_path == "" or not fs.is_directory(folder_path) then
        return { success = false, error = "folder not accessible: " .. tostring(folder_path) }
    end
    local root = sync_root()
    local copied = 0
    for _, e in ipairs(fs.list_recursive(folder_path) or {}) do
        if e.is_file then
            local rel = e.path:sub(#folder_path + 1):gsub("^[/\\]+", "")
            local dst = fs.join(root, rel)
            if not same_size(e.path, dst) then
                pcall(fs.create_directories, fs.parent_path(dst))
                if fs.copy(e.path, dst) then copied = copied + 1 end
            end
        end
    end
    return { success = true, copied = copied }
end

-- ── public IPC ───────────────────────────────────────────────────────────────

function M.get_sync_config()
    return { success = true, config = read_config() }
end

function M.set_sync_config(updates)
    local cfg = read_config()
    if type(updates) ~= "table" then return { success = false, error = "updates must be a dict" } end
    for key, val in pairs(updates) do
        if (key == "git" or key == "folder") and type(val) == "table" and type(cfg[key]) == "table" then
            for k, v in pairs(val) do cfg[key][k] = v end
        else
            cfg[key] = val
        end
    end
    if not write_config(cfg) then return { success = false, error = "write failed" } end
    return { success = true, config = cfg }
end

function M.sync_push()
    local cfg = read_config()
    local backend = cfg.backend or "git"
    local bcfg = cfg[backend] or {}
    local files = collect_data_files(bcfg.include_history_db == true)
    if bcfg.include_lua_scripts ~= false then
        for _, f in ipairs(collect_lua_scripts()) do table.insert(files, f) end
    end
    if #files == 0 then return { success = false, error = "nothing to sync" } end

    local stage = stage_files(files)
    local push
    if backend == "git" then
        local gcfg = cfg.git or {}
        if (gcfg.remote_url or "") == "" then return { success = false, error = "git remote_url not configured" } end
        local init = git_init_or_pull(gcfg.remote_url, gcfg.branch or "main")
        if not init.success then return { success = false, error = init.error } end
        push = git_push(gcfg.branch or "main",
            "LuaTools sync push from " .. (m_utils.getenv("COMPUTERNAME") or "unknown") .. " @ " .. st.fmt_ts(m_utils.time()))
    else
        push = folder_push((cfg.folder or {}).path or "")
    end

    if push.success then cfg.last_push = math.floor(m_utils.time()); write_config(cfg) end
    return {
        success = push.success == true, error = push.error,
        filesStaged = stage.copied + stage.skipped, filesNew = stage.copied,
        stageErrors = stage.errors, backend = backend,
    }
end

function M.sync_pull(dry_run)
    local cfg = read_config()
    local backend = cfg.backend or "git"
    local pull
    if backend == "git" then
        local gcfg = cfg.git or {}
        if (gcfg.remote_url or "") == "" then return { success = false, error = "git remote_url not configured" } end
        pull = git_init_or_pull(gcfg.remote_url, gcfg.branch or "main")
    else
        pull = folder_pull((cfg.folder or {}).path or "")
    end
    if not pull.success then return pull end

    local applied = apply_pulled_files(dry_run == true)
    if applied.success and dry_run ~= true then cfg.last_pull = math.floor(m_utils.time()); write_config(cfg) end
    applied.backend = backend
    return applied
end

function M.sync_status()
    local cfg = read_config()
    local backend = cfg.backend or "git"
    local info = {
        success = true, backend = backend, configured = false,
        lastPush = cfg.last_push or 0, lastPull = cfg.last_pull or 0,
    }
    if backend == "git" then
        local remote = (cfg.git or {}).remote_url or ""
        info.configured = remote ~= ""
        info.remoteUrl = remote
        info.branch = (cfg.git or {}).branch or "main"
        local root = sync_root()
        if fs.is_directory(fs.join(root, ".git")) then
            local code, out = run_git("status --porcelain", root)
            if code == 0 then
                local n = 0
                for line in tostring(out):gmatch("[^\r\n]+") do if st.trim(line) ~= "" then n = n + 1 end end
                info.pendingChanges = n
            end
        end
    else
        local fp = (cfg.folder or {}).path or ""
        info.configured = fp ~= ""
        info.folderPath = fp
    end
    local bcfg = cfg[backend] or {}
    info.localFiles = {
        dataFiles = #collect_data_files(bcfg.include_history_db == true),
        luaScripts = bcfg.include_lua_scripts ~= false and #collect_lua_scripts() or 0,
    }
    return info
end

function M.sync_test_connection()
    local cfg = read_config()
    local backend = cfg.backend or "git"
    if backend == "git" then
        local remote = (cfg.git or {}).remote_url or ""
        if remote == "" then return { success = false, error = "remote_url not configured" } end
        local code, out = run_git('ls-remote "' .. remote .. '"', sync_root())
        if code == 0 then
            local refs = 0
            for line in tostring(out):gmatch("[^\r\n]+") do if st.trim(line) ~= "" then refs = refs + 1 end end
            return { success = true, refs = refs, message = "Remote reachable. " .. refs .. " ref(s)." }
        end
        return { success = false, error = st.trim(out) ~= "" and st.trim(out) or "unknown" }
    else
        local fp = (cfg.folder or {}).path or ""
        if fp == "" then return { success = false, error = "folder path not configured" } end
        if not fs.is_directory(fp) then return { success = false, error = "folder not found: " .. fp } end
        local test = fs.join(fp, ".luatools_write_test")
        local ok = m_utils.write_file(test, "test")
        if ok == false then return { success = false, error = "folder not writable" } end
        pcall(fs.remove, test)
        return { success = true, message = "Folder writable: " .. fp }
    end
end

return M
