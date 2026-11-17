-- Commit a deferred separator together with the following romanized word.
local M = {}

local function enabled(ctx)
  return ctx:get_option("defer_space") and not ctx:get_option("ascii_mode")
end

local function romanized(text)
  if text:match("%s$") then return false end
  local letters = false
  for _, cp in utf8.codes(text) do
    if cp < 128 and utf8.char(cp):match("[A-Za-z]")
        or cp >= 0xC0 and cp <= 0x24F and cp ~= 0xD7 and cp ~= 0xF7
        or cp == 0x1E3E or cp == 0x1E3F then
      letters = true
    elseif cp ~= 32 and cp ~= 45 and cp ~= 39 and cp ~= 0x207F
        and cp ~= 0x1D3A and not (cp >= 0x300 and cp <= 0x36F) then
      return false
    end
  end
  return letters
end

local function punctuation(cp)
  return (cp < 128 and string.char(cp):match("%p") ~= nil)
    or (cp >= 0x2000 and cp <= 0x206F)
    or (cp >= 0x3000 and cp <= 0x303F)
    or (cp >= 0xFF01 and cp <= 0xFF65)
end

local function ends_punctuation(text)
  local last
  for _, cp in utf8.codes(text) do last = cp end
  return last ~= nil and punctuation(last)
end

function M.init(env)
  env.pending_space = false
  local ctx = env.engine.context
  env.commit_connection = ctx.commit_notifier:connect(function(context)
    local text = context:get_commit_text()
    local active = enabled(context) and text:sub(-1) ~= "-"
      and (romanized(text) or ends_punctuation(text))
    context:set_property("lomaji_space_prefix", "")
    env.pending_space = active
  end)
  env.option_connection = ctx.option_update_notifier:connect(function(context)
    if not enabled(context) or not context:get_option("defer_space") then
      env.pending_space = false
      context:set_property("lomaji_space_prefix", "")
    end
  end)
  env.update_connection = ctx.update_notifier:connect(function(context)
    if not context:is_composing() and context:get_property("lomaji_space_prefix") ~= "" then
      context:set_property("lomaji_space_prefix", "")
    end
  end)
end

function M.func(key, env)
  if key:release() then return 2 end
  local ctx = env.engine.context
  if not enabled(ctx) then
    env.pending_space = false
    return 2
  end
  if key.keycode == 0xFF0D and not key:ctrl() and not key:alt()
      and ctx:get_property("lomaji_space_prefix") == "1" and ctx:has_menu() then
    ctx:commit()
    return 1
  end
  if key.keycode == 0xFFE1 or key.keycode == 0xFFE2 then return 2 end
  -- Navigation, shortcuts and editing cancel the pending separator. Never send
  -- BackSpace to an application or assume its cursor still follows our commit.
  if key:ctrl() or key:alt() or key:super() then
    env.pending_space = false
    return 2
  end
  local cp = key.keycode
  if cp >= 0x1000000 then cp = cp - 0x1000000 end
  if cp == 45 then
    env.pending_space = false
    return 2
  end
  -- Literal punctuation can pass directly to the application without a commit
  -- notification. Remember it here as well as in the commit callback.
  if (cp < 0xFF00 or key.keycode >= 0x1000000)
      and punctuation(cp) and not ctx:is_composing() then
    env.pending_space = true
    return 2
  end
  if not env.pending_space then return 2 end
  env.pending_space = false
  if cp < 33 or cp >= 0xFF00 and cp <= 0xFFFF or punctuation(cp) then return 2 end
  if cp <= 0x10FFFF and (cp < 127 or cp >= 0xA0) then
    ctx:set_property("lomaji_space_prefix", "1")
  end
  return 2
end

M.filter = {
  func = function(input, env)
    local ctx = env.engine.context
    for cand in input:iter() do
      if enabled(ctx) and ctx:get_property("lomaji_space_prefix") == "1"
          and cand._start == 0 and romanized(cand.text) then
        yield(ShadowCandidate(cand, cand.type, " " .. cand.text, cand.comment))
      else
        yield(cand)
      end
    end
  end,
}

function M.fini(env)
  if env.commit_connection then env.commit_connection:disconnect() end
  if env.option_connection then env.option_connection:disconnect() end
  if env.update_connection then env.update_connection:disconnect() end
  env.pending_space = false
end

return M
