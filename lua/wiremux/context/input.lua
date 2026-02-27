local M = {}

---Parse an input key into prompt and default value
---Key formats: "input", "input:Prompt", "input:Prompt:default"
---@param key string The full key (e.g. "input:Branch:main")
---@return string prompt
---@return string? default
function M.parse(key)
    if key == "input" then
        return "Input", nil
    end

    -- Strip "input:" prefix
    local rest = key:sub(#"input:" + 1)

    -- Find first colon for prompt:default split
    local colon_pos = rest:find(":", 1, true)
    if not colon_pos then
        return rest, nil
    end

    local prompt = rest:sub(1, colon_pos - 1)
    local default = rest:sub(colon_pos + 1)

    return prompt, default
end

---Find all unique input placeholder keys in text
---Returns keys in order of first appearance
---@param text string
---@return string[]
function M.find(text)
    if not text:find("{input", 1, true) then
        return {}
    end

    local seen = {}
    local keys = {}

    -- Match {input...} placeholders — capture everything between { and }
    for content in text:gmatch("{(input[^}]*)}") do
        -- Reject names like {input_var} or {input2} — only allow bare "input" or "input:..."
        if content == "input" or content:sub(1, 6) == "input:" then
            if not seen[content] then
                seen[content] = true
                table.insert(keys, content)
            end
        end
    end

    return keys
end

---Quick check if text contains any input placeholders
---@param text string
---@return boolean
function M.has_inputs(text)
    return #M.find(text) > 0
end

---Replace input placeholders in text with resolved values
---Only replaces placeholders whose keys exist in the values table
---@param text string
---@param values table<string, string>
---@return string
function M.replace(text, values)
    return text:gsub("{(input[^}]*)}", function(content)
        if content == "input" or content:sub(1, 6) == "input:" then
            if values[content] ~= nil then
                return values[content]
            end
        end
        -- Leave non-input or unresolved placeholders intact
        return "{" .. content .. "}"
    end)
end

---Resolve input placeholders by chaining vim.ui.input() calls
---Calls on_done(values) with a table of key→value, or on_done(nil) if user cancels
---@param keys string[] Unique input keys to resolve
---@param on_done fun(values: table<string, string>|nil)
function M.resolve(keys, on_done)
    local values = {}
    local i = 0

    local function next_input()
        i = i + 1
        if i > #keys then
            on_done(values)
            return
        end

        local key = keys[i]
        local prompt, default = M.parse(key)

        vim.ui.input({
            prompt = prompt .. ": ",
            default = default or "",
        }, function(value)
            if value == nil then
                on_done(nil)
                return
            end
            values[key] = value
            next_input()
        end)
    end

    next_input()
end

return M
