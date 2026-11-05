-- rex-autogroup: keep sessions of the same git project adjacent in the
-- session list (Rex has no sidebar groups, so adjacency is the grouping).
-- Port of cmux-autogroup's project derivation: `git rev-parse --git-common-dir`
-- puts a repo and all its worktrees in one project; a non-git cwd falls back
-- to its own resolved path.
--
-- Run:  rex do autogroup.lua --all            (add dry=true to only log)
-- Never renames or closes sessions; it only calls session.move.

local DRY = rex.args and rex.args.dry == true
local DEBOUNCE, FORCE_EVERY = 0.3, 60
local LOG = (os.getenv("HOME") or "") .. "/.local/state/rex-autogroup.log"

local function log(msg)
  local f = io.open(LOG, "a")
  if f then f:write(os.date("%Y-%m-%dT%H:%M:%S "), msg, "\n"); f:close() end
end

local cwd_of = {}      -- session_id -> cwd (from terminal.pwd_changed)
local project_cache = {} -- cwd -> project key

local function parse_pwd(url)
  local path = url:match("^file://[^/]*(/.*)$") or url
  return (path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function project_of(cwd)
  if project_cache[cwd] then return project_cache[cwd] end
  local key = cwd
  local r = rex.exec({ "git", "rev-parse", "--path-format=absolute", "--git-common-dir" },
                     { cwd = cwd, timeout = 5 })
  if r and r.ok then
    key = r.stdout:gsub("%s+$", "")
  else
    local p = rex.exec({ "realpath", cwd }, { timeout = 5 })
    if p and p.ok then key = p.stdout:gsub("%s+$", "") end
  end
  project_cache[cwd] = key
  return key
end

-- Learn a session's cwd from its first terminal block (needed for sessions that
-- existed before this script started and have not changed directory since).
local function seed_cwd(session_id)
  local ok, res = pcall(rex.call, "session.list_blocks", { session_id = session_id })
  if not ok or not res or not res.blocks then return end
  for _, b in ipairs(res.blocks) do
    if b.creator_name == "com.superlogical.terminal" then
      local ok2, r = pcall(rex.call, "com.superlogical.terminal.pwd",
                           { session_id = session_id, block_id = b.block_id, args = {} })
      if ok2 and r and r.pwd then cwd_of[session_id] = parse_pwd(r.pwd) end
      return
    end
  end
end

local function sweep()
  local list = rex.call("session.list", {}).sessions
  if not list then return end
  for _, s in ipairs(list) do
    if not cwd_of[s.session_id] then seed_cwd(s.session_id) end
  end
  local current, first_idx, groups, order = {}, {}, {}, {}
  for i, s in ipairs(list) do
    current[i] = s.session_id
    local cwd = cwd_of[s.session_id]
    local key = cwd and project_of(cwd) or ("session:" .. s.session_id) -- unknown cwd: own group
    if not groups[key] then groups[key] = {}; order[#order + 1] = key end
    table.insert(groups[key], s.session_id)
  end
  local target = {}
  for _, key in ipairs(order) do
    for _, id in ipairs(groups[key]) do target[#target + 1] = id end
  end
  for i = 1, #target do
    if current[i] ~= target[i] then
      if DRY then
        log("dry: move " .. target[i] .. " before " .. current[i])
      else
        rex.call("session.move", { session_id = target[i], before_session_id = current[i] })
        log("moved " .. target[i] .. " before " .. current[i])
      end
      -- keep our model of the order in sync
      for j = i + 1, #current do
        if current[j] == target[i] then table.remove(current, j); break end
      end
      table.insert(current, i, target[i])
    end
  end
end

local pending = false
local function schedule()
  if pending then return end
  pending = true
  rex.after(DEBOUNCE, function()
    pending = false
    local ok, err = pcall(sweep)
    if not ok then log("sweep failed: " .. tostring(err)) end
  end)
end

pcall(rex.call, "session.attach_all", {})

rex.on("terminal.pwd_changed", function(ctx, ev)
  if ev.session_id and ev.pwd then
    cwd_of[ev.session_id] = parse_pwd(ev.pwd)
    schedule()
  end
end)
rex.on("session_created", schedule)
rex.on("session_destroyed", function(ctx, ev)
  if ev.session and ev.session.session_id then cwd_of[ev.session.session_id] = nil end
  schedule()
end)
rex.every(FORCE_EVERY, schedule)

schedule()
log("autogroup started" .. (DRY and " (dry-run)" or ""))
