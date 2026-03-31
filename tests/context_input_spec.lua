---@module 'luassert'

describe("context.input", function()
    local input

    before_each(function()
        package.loaded["wiremux.context.input"] = nil
        input = require("wiremux.context.input")
    end)

    describe("parse", function()
        it("returns default prompt for bare input", function()
            local prompt, default = input.parse("input")
            assert.are.equal("Input", prompt)
            assert.is_nil(default)
        end)

        it("returns custom prompt without default", function()
            local prompt, default = input.parse("input:Enter branch name")
            assert.are.equal("Enter branch name", prompt)
            assert.is_nil(default)
        end)

        it("returns prompt and default", function()
            local prompt, default = input.parse("input:Branch:main")
            assert.are.equal("Branch", prompt)
            assert.are.equal("main", default)
        end)

        it("handles default with colons", function()
            local prompt, default = input.parse("input:URL:http://localhost:8080")
            assert.are.equal("URL", prompt)
            assert.are.equal("http://localhost:8080", default)
        end)
    end)

    describe("find", function()
        it("returns empty for text without input placeholders", function()
            local keys = input.find("echo hello {file}")
            assert.are.equal(0, #keys)
        end)

        it("finds bare {input}", function()
            local keys = input.find("echo {input}")
            assert.are.equal(1, #keys)
            assert.are.equal("input", keys[1])
        end)

        it("finds {input:prompt}", function()
            local keys = input.find("git checkout {input:Branch}")
            assert.are.equal(1, #keys)
            assert.are.equal("input:Branch", keys[1])
        end)

        it("finds {input:prompt:default}", function()
            local keys = input.find("git checkout {input:Branch:main}")
            assert.are.equal(1, #keys)
            assert.are.equal("input:Branch:main", keys[1])
        end)

        it("deduplicates same placeholder", function()
            local keys = input.find("{input} and {input}")
            assert.are.equal(1, #keys)
            assert.are.equal("input", keys[1])
        end)

        it("finds multiple distinct inputs", function()
            local keys = input.find("mv {input:Source} {input:Destination}")
            assert.are.equal(2, #keys)
            assert.are.equal("input:Source", keys[1])
            assert.are.equal("input:Destination", keys[2])
        end)

        it("ignores non-input placeholders like {input_var}", function()
            local keys = input.find("{input_var} and {input}")
            assert.are.equal(1, #keys)
            assert.are.equal("input", keys[1])
        end)

        it("ignores {input2} style names", function()
            local keys = input.find("{input2} test")
            assert.are.equal(0, #keys)
        end)
    end)

    describe("has_inputs", function()
        it("returns false for plain text", function()
            assert.is_false(input.has_inputs("no placeholders"))
        end)

        it("returns false for non-input placeholders", function()
            assert.is_false(input.has_inputs("{file} and {line}"))
        end)

        it("returns true for bare input", function()
            assert.is_true(input.has_inputs("echo {input}"))
        end)

        it("returns true for input with prompt", function()
            assert.is_true(input.has_inputs("{input:Name}"))
        end)
    end)

    describe("replace", function()
        it("replaces bare input", function()
            local result = input.replace("echo {input}", { input = "hello" })
            assert.are.equal("echo hello", result)
        end)

        it("replaces input with prompt", function()
            local result = input.replace("git checkout {input:Branch}", { ["input:Branch"] = "develop" })
            assert.are.equal("git checkout develop", result)
        end)

        it("replaces duplicate placeholders", function()
            local result = input.replace("{input} and {input}", { input = "val" })
            assert.are.equal("val and val", result)
        end)

        it("replaces multiple distinct inputs", function()
            local result = input.replace("mv {input:From} {input:To}", {
                ["input:From"] = "a.txt",
                ["input:To"] = "b.txt",
            })
            assert.are.equal("mv a.txt b.txt", result)
        end)

        it("leaves unresolved input placeholders intact", function()
            local result = input.replace("{input:A} {input:B}", { ["input:A"] = "resolved" })
            assert.are.equal("resolved {input:B}", result)
        end)

        it("does not touch non-input placeholders", function()
            local result = input.replace("{file} {input}", { input = "val" })
            assert.are.equal("{file} val", result)
        end)
    end)

    describe("resolve", function()
        it("collects values from vim.ui.input", function()
            local input_calls = {}
            vim.ui.input = function(opts, callback)
                table.insert(input_calls, opts)
                callback("user_value")
            end

            local result
            input.resolve({ "input" }, function(values)
                result = values
            end)

            assert.are.equal(1, #input_calls)
            assert.are.equal("Input: ", input_calls[1].prompt)
            assert.are.equal("", input_calls[1].default)
            assert.is_not_nil(result)
            assert.are.equal("user_value", result["input"])
        end)

        it("passes prompt and default to vim.ui.input", function()
            local input_calls = {}
            vim.ui.input = function(opts, callback)
                table.insert(input_calls, opts)
                callback("val")
            end

            input.resolve({ "input:Branch:main" }, function() end)

            assert.are.equal("Branch: ", input_calls[1].prompt)
            assert.are.equal("main", input_calls[1].default)
        end)

        it("chains multiple inputs sequentially", function()
            local call_count = 0
            vim.ui.input = function(opts, callback)
                call_count = call_count + 1
                callback("val" .. call_count)
            end

            local result
            input.resolve({ "input:A", "input:B" }, function(values)
                result = values
            end)

            assert.are.equal(2, call_count)
            assert.are.equal("val1", result["input:A"])
            assert.are.equal("val2", result["input:B"])
        end)

        it("calls on_done(nil) when user cancels", function()
            vim.ui.input = function(opts, callback)
                callback(nil)
            end

            local result = "not_called"
            input.resolve({ "input" }, function(values)
                result = values
            end)

            assert.is_nil(result)
        end)

        it("aborts remaining inputs on cancel", function()
            local call_count = 0
            vim.ui.input = function(opts, callback)
                call_count = call_count + 1
                if call_count == 1 then
                    callback("first")
                else
                    callback(nil)
                end
            end

            local result = "not_called"
            input.resolve({ "input:A", "input:B", "input:C" }, function(values)
                result = values
            end)

            assert.are.equal(2, call_count)
            assert.is_nil(result)
        end)

        it("calls on_done immediately for empty keys", function()
            local result
            input.resolve({}, function(values)
                result = values
            end)

            assert.is_not_nil(result)
            assert.are.equal(0, vim.tbl_count(result))
        end)
    end)
end)
