-- ---------------------------------------------------------------------------
-- LightsOutBoard — game state and logic for Lights Out.
--
-- Pressing a cell toggles it and its four orthogonal neighbours; the goal
-- is to switch every light off. Puzzles are made by pressing random cells
-- of a dark board, so every one can be solved. Win detection is simply
-- "no light on": any sequence of presses that gets there wins.
--
-- The optimal number of presses, the hint and "Show solution" all come from
-- gf2.lua, which finds the smallest set of cells to press from any position.
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local UndoStack = require("undo_stack")
local Timer     = require("timer")
local Hint      = require("hint")
local GF2       = lrequire("gf2")

local SIZES     = { 5, 6, 7, 8, 9 }
local DEFAULT_N = 5

-- How many random cells are pressed to build the puzzle, by difficulty.
-- "hard" presses each cell with probability 1/2, which gives a uniformly
-- random solvable board -- typically half the grid or so to press.
local PRESSES = {
    easy   = function(n) return math.max(3, n - 1) end,
    medium = function(n) return 2 * n end,
}

local LightsOutBoard = {}
LightsOutBoard.__index = LightsOutBoard

function LightsOutBoard:new(opts)
    opts = opts or {}
    local n = opts.n or DEFAULT_N
    local b = setmetatable({
        n             = n,
        rows          = n,
        cols          = n,
        difficulty    = opts.difficulty or "easy",
        lights        = {},    -- lights[r][c] = true when lit
        start         = {},    -- flat 0/1 copy of the starting board
        par           = 0,     -- fewest presses that solve the start
        moves         = 0,
        hints_used    = 0,
        show_solution = false,
        selected      = nil,
        undo_stack    = UndoStack:new(),
        timer         = Timer:new(),
        _plan_key     = nil,   -- cache for getPlan()
        _plan         = nil,
        _plan_w       = nil,
    }, self)
    for r = 1, n do
        b.lights[r] = {}
        for c = 1, n do b.lights[r][c] = false end
    end
    return b
end

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

-- Toggle (r, c) and its neighbours, with no bookkeeping.
function LightsOutBoard:_toggle(r, c)
    local n, L = self.n, self.lights
    L[r][c] = not L[r][c]
    if r > 1 then L[r - 1][c] = not L[r - 1][c] end
    if r < n then L[r + 1][c] = not L[r + 1][c] end
    if c > 1 then L[r][c - 1] = not L[r][c - 1] end
    if c < n then L[r][c + 1] = not L[r][c + 1] end
end

-- A player's press: counted, undoable. Refused once the board is dark.
function LightsOutBoard:press(r, c)
    if self:isSolved() then return false end
    self:_toggle(r, c)
    self.undo_stack:push({ r = r, c = c })
    self.moves = self.moves + 1
    self.selected = nil
    if not self.timer:isRunning() then self.timer:start() end
    if self:isSolved() then self.timer:stop() end
    return true
end

function LightsOutBoard:canUndo()
    return self.undo_stack:canUndo() and not self:isSolved()
end

-- A press is its own inverse, so undoing is pressing again.
function LightsOutBoard:undo()
    if not self:canUndo() then return false end
    local e = self.undo_stack:pop()
    self:_toggle(e.r, e.c)
    self.moves = math.max(0, self.moves - 1)
    self.selected = nil
    return true
end

function LightsOutBoard:countLit()
    local k = 0
    for r = 1, self.n do
        for c = 1, self.n do
            if self.lights[r][c] then k = k + 1 end
        end
    end
    return k
end

function LightsOutBoard:isSolved()
    return self.lights[1] ~= nil and self:countLit() == 0
end

function LightsOutBoard:_flat()
    local out, n = {}, self.n
    for r = 1, n do
        for c = 1, n do out[(r - 1) * n + c] = self.lights[r][c] and 1 or 0 end
    end
    return out
end

function LightsOutBoard:_setFlat(flat)
    local n = self.n
    for r = 1, n do
        self.lights[r] = self.lights[r] or {}
        for c = 1, n do self.lights[r][c] = flat[(r - 1) * n + c] == 1 end
    end
end

-- ---------------------------------------------------------------------------
-- Generation
-- ---------------------------------------------------------------------------

function LightsOutBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty
    local n, N = self.n, self.n * self.n
    local count = PRESSES[self.difficulty]
    repeat
        for r = 1, n do
            for c = 1, n do self.lights[r][c] = false end
        end
        if count then
            -- k distinct random cells (partial Fisher-Yates).
            local cells = {}
            for i = 1, N do cells[i] = i end
            for i = 1, math.min(count(n), N) do
                local j = math.random(i, N)
                cells[i], cells[j] = cells[j], cells[i]
                self:_toggle(math.floor((cells[i] - 1) / n) + 1, (cells[i] - 1) % n + 1)
            end
        else
            for r = 1, n do
                for c = 1, n do
                    if math.random(2) == 1 then self:_toggle(r, c) end
                end
            end
        end
        -- Presses can cancel out (on 5x5 and 9x9 some sets do nothing), so
        -- the optimum may be below the count pressed; a dark board or a
        -- one-press puzzle is not worth playing.
        local _, w = GF2.solve(n, self:_flat())
        self.par = w or 0
    until self.par >= 2

    self.start         = self:_flat()
    self.moves         = 0
    self.hints_used    = 0
    self.show_solution = false
    self.selected      = nil
    self._plan_key     = nil
    self.undo_stack:clear()
    self.timer:reset()
    self.timer:start()
end

-- Back to the starting board.
function LightsOutBoard:restart()
    self:_setFlat(self.start)
    self.moves    = 0
    self.selected = nil
    self.undo_stack:clear()
    self.timer:start()
end

-- ---------------------------------------------------------------------------
-- Solution
-- ---------------------------------------------------------------------------

-- Fewest presses from the current board: plan[r][c] = true for each cell to
-- press, plus the count. Cached on the board's contents, since the hint
-- module asks once per cell.
function LightsOutBoard:getPlan()
    local flat = self:_flat()
    local key = table.concat(flat)
    if self._plan_key ~= key then
        local x, w = GF2.solve(self.n, flat)
        local plan = {}
        for r = 1, self.n do
            plan[r] = {}
            for c = 1, self.n do
                plan[r][c] = x ~= nil and x[(r - 1) * self.n + c] == 1
            end
        end
        self._plan_key, self._plan, self._plan_w = key, plan, w or 0
    end
    return self._plan, self._plan_w
end

function LightsOutBoard:isShowingSolution()
    return self.show_solution
end

function LightsOutBoard:toggleSolution()
    self.show_solution = not self.show_solution
    self.selected = nil
end

function LightsOutBoard:setSelection(r, c)
    self.selected = { r = r, c = c }
end

-- ---------------------------------------------------------------------------
-- Hints: point at a cell of the optimal plan, then press it. No cell is ever
-- "wrong" here (any press can be undone by pressing again), so the player's
-- side is always empty and every hint is a fill.
-- ---------------------------------------------------------------------------

Hint.install(LightsOutBoard, {
    getUser     = function() return nil end,
    getSolution = function(b, r, c) return b:getPlan()[r][c] or nil end,
    setCell     = function(b, r, c) return b:press(r, c) end,
})

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function LightsOutBoard:serialize()
    -- Timer:serialize stops the clock to bank the elapsed time; keep it
    -- running, since saving happens after every press.
    local timer = self.timer:serialize()
    if timer.was_running then self.timer:start() end
    return {
        n          = self.n,
        difficulty = self.difficulty,
        lights     = self:_flat(),
        start      = self.start,
        par        = self.par,
        moves      = self.moves,
        hints_used = self.hints_used,
        timer      = timer,
        undo       = self.undo_stack:serialize(),
    }
end

function LightsOutBoard:load(data)
    if type(data) ~= "table" or not data.n or type(data.lights) ~= "table" then
        return false
    end
    local n = data.n
    if #data.lights ~= n * n then return false end
    self.n, self.rows, self.cols = n, n, n
    self.lights = {}
    self:_setFlat(data.lights)
    self.difficulty    = data.difficulty or self.difficulty
    self.start         = (type(data.start) == "table" and #data.start == n * n)
                         and data.start or self:_flat()
    self.par           = data.par or select(2, GF2.solve(n, self.start)) or 0
    self.moves         = data.moves or 0
    self.hints_used    = data.hints_used or 0
    self.show_solution = false
    self.selected      = nil
    self._plan_key     = nil
    self.timer         = Timer:new()
    if data.timer then self.timer:load(data.timer) end
    self.undo_stack:load(data.undo)
    return true
end

LightsOutBoard.SIZES     = SIZES
LightsOutBoard.DEFAULT_N = DEFAULT_N

return LightsOutBoard
