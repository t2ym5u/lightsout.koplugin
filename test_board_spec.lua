local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("Lights Out", function()
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

    describe("rules", function()
        it("a press toggles the cell and its orthogonal neighbours only", function()
            local b = Board:new{ n = 5 }
            b:_toggle(3, 3)
            assert.is_true(b.lights[3][3])
            assert.is_true(b.lights[2][3])
            assert.is_true(b.lights[4][3])
            assert.is_true(b.lights[3][2])
            assert.is_true(b.lights[3][4])
            assert.is_false(b.lights[2][2])
            assert.are.equal(5, b:countLit())
        end)

        it("a corner press toggles three cells", function()
            local b = Board:new{ n = 5 }
            b:_toggle(1, 1)
            assert.are.equal(3, b:countLit())
        end)

        it("undo presses again and takes the move back", function()
            local b = newBoard(5, "medium", 1)
            local before = b:_flat()
            b:press(2, 4)
            assert.are.equal(1, b.moves)
            assert.is_true(b:undo())
            assert.are.same(before, b:_flat())
            assert.are.equal(0, b.moves)
        end)

        it("restart returns to the starting board", function()
            local b = newBoard(6, "medium", 2)
            local start = b:_flat()
            b:press(1, 1); b:press(4, 5)
            b:restart()
            assert.are.same(start, b:_flat())
            assert.are.equal(0, b.moves)
            assert.is_false(b:canUndo())
        end)
    end)

    describe("win detection", function()
        it("is solved exactly when every light is off", function()
            local b = Board:new{ n = 5 }
            assert.is_true(b:isSolved())
            b:_toggle(2, 2)
            assert.is_false(b:isSolved())
            assert.is_true(b:press(2, 2))
            assert.is_true(b:isSolved())
        end)

        it("accepts any solving sequence, not only the optimal one", function()
            -- 5x5 has a 2-dimensional null space: a solution plus a
            -- "quiet" pattern is another, longer solution that must win too.
            local b = newBoard(5, "hard", 3)
            local x = GF2.solve(5, b:_flat())
            local quiet = { 0,1,1,1,0, 1,0,1,0,1, 1,1,0,1,1, 1,0,1,0,1, 0,1,1,1,0 }
            assert.is_true(isDark(applyPresses(5, (function() local z = {} for i = 1, 25 do z[i] = 0 end return z end)(), quiet)))
            for i = 1, 25 do
                if (x[i] + quiet[i]) % 2 == 1 then
                    b:press(math.floor((i - 1) / 5) + 1, (i - 1) % 5 + 1)
                end
            end
            assert.is_true(b:isSolved())
        end)

        it("refuses presses once solved", function()
            local b = Board:new{ n = 5 }
            assert.is_false(b:press(1, 1))
        end)
    end)

    describe("GF(2) solver", function()
        it("knows the classic null-space sizes", function()
            assert.are.equal(2, GF2.nullity(5))
            assert.are.equal(0, GF2.nullity(6))
            assert.are.equal(0, GF2.nullity(7))
            assert.are.equal(0, GF2.nullity(8))
            assert.are.equal(8, GF2.nullity(9))
        end)

        it("finds the true minimum, checked by brute force on 3x3 and 4x4", function()
            for _, n in ipairs({ 3, 4 }) do
                local N = n * n
                -- best[board key] = fewest presses reaching it from dark
                local best = {}
                for mask = 0, 2 ^ N - 1 do
                    local x, m, w = {}, mask, 0
                    for i = 1, N do x[i] = m % 2; w = w + x[i]; m = math.floor(m / 2) end
                    local zero = {}
                    for i = 1, N do zero[i] = 0 end
                    local key = table.concat(applyPresses(n, zero, x))
                    if not best[key] or w < best[key] then best[key] = w end
                end
                math.randomseed(n)
                for _ = 1, 40 do
                    local b = {}
                    for i = 1, N do b[i] = math.random(0, 1) end
                    local x, w = GF2.solve(n, b)
                    local key = table.concat(b)
                    if best[key] then
                        assert.are.equal(best[key], w)
                        assert.is_true(isDark(applyPresses(n, b, x)))
                    else
                        assert.is_nil(x)
                    end
                end
            end
        end)

        it("reports an unreachable 5x5 board as unsolvable", function()
            -- A single lit corner is not reachable on 5x5.
            local b = {}
            for i = 1, 25 do b[i] = 0 end
            b[1] = 1
            assert.is_nil(GF2.solve(5, b))
        end)
    end)

    describe("generate", function()
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
    end)

    describe("hints", function()
        it("following hints solves the board in exactly the optimal count", function()
            for _, n in ipairs({ 5, 7, 9 }) do
                local b = newBoard(n, "hard", n)
                local guard = 0
                while not b:isSolved() and guard < 100 do
                    local step = b:findHint()
                    assert.is_not_nil(step)
                    assert.are.equal("fill", step.kind)
                    assert.is_true(b:applyHint(step))
                    guard = guard + 1
                end
                assert.is_true(b:isSolved())
                assert.are.equal(b.par, b.moves)
            end
        end)

        it("says complete when nothing is lit", function()
            local b = Board:new{ n = 5 }
            local step, reason = b:findHint()
            assert.is_nil(step)
            assert.are.equal("complete", reason)
        end)

        it("is deterministic", function()
            local b = newBoard(5, "medium", 4)
            local a, c = b:findHint(), b:findHint()
            assert.are.equal(a.r, c.r)
            assert.are.equal(a.c, c.c)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips lights, start, par and undo", function()
            local b = newBoard(6, "medium", 5)
            b:press(2, 2)
            local data = b:serialize()
            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(6, b2.n)
            assert.are.same(b.lights, b2.lights)
            assert.are.same(b.start, b2.start)
            assert.are.equal(b.par, b2.par)
            assert.are.equal(1, b2.moves)
            assert.is_true(b2:undo())
            b2:restart()
            assert.are.same(b.start, b2:_flat())
        end)

        it("rejects missing or truncated data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
            assert.is_false(b:load({ n = 5, lights = { 1, 0 } }))
        end)
    end)
end)
