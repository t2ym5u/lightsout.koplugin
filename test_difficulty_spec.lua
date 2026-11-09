local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

-- Difficulty guarantees: every size x level builds a solvable, unsolved
-- board whose optimum (par, from the GF(2) solver) grows with the level on
-- average, 5x5 keeps its three levels apart, and a seed always builds the
-- same board without reading the clock.
local LEVELS = { "easy", "medium", "hard" }

-- Runs fn with os.clock/os.time wrapped; returns how often they were read.
local function clockReads(fn)
    local clock, time = os.clock, os.time
    local reads = 0
    os.clock = function() reads = reads + 1; return clock() end
    os.time = function(...) reads = reads + 1; return time(...) end
    local ok, err = pcall(fn)
    os.clock, os.time = clock, time
    assert(ok, err)
    return reads
end

describe("Lights Out difficulty", function()
    local Board, GF2

    setup(function()
        Board = dofile(DIR .. "board.lua")
        GF2   = dofile(DIR .. "gf2.lua")
    end)

    local function newBoard(n, diff, seed)
        math.randomseed(seed or 42)
        local b = Board:new{ n = n or 5 }
        b:generate(diff or "easy")
        return b
    end

    -- Apply a flat 0/1 press vector to a flat 0/1 board (no bookkeeping).
    local function applyPresses(n, board, x)
        local out = {}
        for i = 1, n * n do out[i] = board[i] end
        for i = 1, n * n do
            if x[i] == 1 then
                local r, c = math.floor((i - 1) / n) + 1, (i - 1) % n + 1
                local function flip(rr, cc)
                    if rr >= 1 and rr <= n and cc >= 1 and cc <= n then
                        local j = (rr - 1) * n + cc
                        out[j] = 1 - out[j]
                    end
                end
                flip(r, c); flip(r - 1, c); flip(r + 1, c); flip(r, c - 1); flip(r, c + 1)
            end
        end
        return out
    end

    local function isDark(v)
        for i = 1, #v do if v[i] == 1 then return false end end
        return true
    end

        it("always gives a solvable, unsolved board whose plan solves it", function()
            for _, n in ipairs(Board.SIZES) do
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    for seed = 1, 10 do
                        local b = newBoard(n, diff, seed)
                        assert.is_false(b:isSolved())
                        local x, w = GF2.solve(n, b:_flat())
                        assert.is_not_nil(x)
                        assert.are.equal(b.par, w)
                        assert.is_true(b.par >= 2)
                        assert.is_true(isDark(applyPresses(n, b:_flat(), x)))
                    end
                end
            end
        end)

        it("easy needs fewer presses than hard", function()
            local easy, hard = 0, 0
            for seed = 1, 20 do
                easy = easy + newBoard(7, "easy", seed).par
                hard = hard + newBoard(7, "hard", seed).par
            end
            assert.is_true(easy < hard)
        end)

        -- 5x5 Medium (2n = 10 presses) used to need as many presses as Hard
        -- (9.6 against 9.9 on average): the levels must not overlap there.
        it("keeps the three 5x5 levels apart", function()
            for seed = 1, 60 do
                local e = newBoard(5, "easy", seed).par
                local m = newBoard(5, "medium", seed).par
                local h = newBoard(5, "hard", seed).par
                assert.is_true(e <= 4, "easy " .. e)
                assert.is_true(m >= 6 and m <= 7, "medium " .. m)
                assert.is_true(h >= 12 and h <= 15, "hard " .. h)
            end
        end)

        it("is the same puzzle for the same seed on 5x5 Hard", function()
            local a = newBoard(5, "hard", 77)
            local b = newBoard(5, "hard", 77)
            assert.are.same(a.start, b.start)
        end)
    it("orders Easy < Medium < Hard on average par, for every size", function()
        for _, n in ipairs(Board.SIZES) do
            local prev = 0
            for _, diff in ipairs(LEVELS) do
                local sum = 0
                for seed = 1, 8 do sum = sum + newBoard(n, diff, seed).par end
                assert.is_true(sum / 8 > prev, ("%dx%d %s: %.1f"):format(n, n, diff, sum / 8))
                prev = sum / 8
            end
        end
    end)

    it("is the same puzzle for the same seed, every size and level", function()
        for _, n in ipairs(Board.SIZES) do
            for _, diff in ipairs(LEVELS) do
                assert.are.same(newBoard(n, diff, 5).start, newBoard(n, diff, 5).start)
            end
        end
    end)

    it("generation never reads the clock", function()
        -- The board's own move timer starts after the puzzle is built:
        -- only the building itself is watched.
        for _, diff in ipairs(LEVELS) do
            local b = Board:new{ n = 6 }
            b.timer = { reset = function() end, start = function() end }
            local reads = clockReads(function()
                math.randomseed(3)
                b:generate(diff)
            end)
            assert.are.equal(0, reads, diff)
        end
    end)
end)
