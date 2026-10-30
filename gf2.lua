-- ---------------------------------------------------------------------------
-- GF(2) linear algebra for Lights Out.
--
-- Pressing a cell toggles it and its orthogonal neighbours, and pressing
-- twice undoes itself, so a sequence of presses is just the set of cells
-- pressed an odd number of times, in any order. Over GF(2) (arithmetic mod
-- 2) the board is the vector b of lit cells, each press a column of the
-- n²×n² "press matrix" A, and a solution any x with A·x = b.
--
-- Gaussian elimination gives one solution plus a basis of the null space of
-- A (press sets that change nothing: 2 of them on 5×5, 8 on 9×9, none on
-- 6×6..8×8). Every solution is the particular one plus a combination of the
-- basis, so trying all 2^k combinations finds the one with fewest presses:
-- the optimal number of moves.
--
-- Vectors are plain Lua arrays of 0/1, indexed by cell (r-1)*n + c.
-- ---------------------------------------------------------------------------

local GF2 = {}

-- Reduced row-echelon form of A for size n, computed once per n: the
-- elimination steps only depend on A, so they are recorded and replayed on
-- each right-hand side.
local cache = {}

local function pressMatrix(n)
    local N, A = n * n, {}
    for r = 1, n do
        for c = 1, n do
            local i = (r - 1) * n + c
            local row = {}
            for j = 1, N do row[j] = 0 end
            -- Row i: which presses toggle cell i -- itself and its
            -- neighbours (the matrix is symmetric).
            row[i] = 1
            if r > 1 then row[i - n] = 1 end
            if r < n then row[i + n] = 1 end
            if c > 1 then row[i - 1] = 1 end
            if c < n then row[i + 1] = 1 end
            A[i] = row
        end
    end
    return A
end

local function prepare(n)
    if cache[n] then return cache[n] end
    local N = n * n
    local A = pressMatrix(n)
    -- T tracks the row operations (starts as the identity), so that
    -- T·b is the right-hand side after elimination.
    local T = {}
    for i = 1, N do
        T[i] = {}
        for j = 1, N do T[i][j] = (i == j) and 1 or 0 end
    end
    local pivots, row = {}, 1
    for col = 1, N do
        local p
        for k = row, N do
            if A[k][col] == 1 then p = k; break end
        end
        if p then
            A[row], A[p] = A[p], A[row]
            T[row], T[p] = T[p], T[row]
            for k = 1, N do
                if k ~= row and A[k][col] == 1 then
                    local ak, ar, tk, tr = A[k], A[row], T[k], T[row]
                    for j = 1, N do
                        if ar[j] == 1 then ak[j] = 1 - ak[j] end
                        if tr[j] == 1 then tk[j] = 1 - tk[j] end
                    end
                end
            end
            pivots[#pivots + 1] = col
            row = row + 1
        end
    end
    local rank = #pivots
    local is_pivot = {}
    for _, col in ipairs(pivots) do is_pivot[col] = true end
    -- Null space basis: one vector per free column f, with x_f = 1 and each
    -- pivot variable set to cancel it.
    local basis = {}
    for f = 1, N do
        if not is_pivot[f] then
            local v = {}
            for j = 1, N do v[j] = 0 end
            v[f] = 1
            for k = 1, rank do
                if A[k][f] == 1 then v[pivots[k]] = 1 end
            end
            basis[#basis + 1] = v
        end
    end
    local prep = { n = n, N = N, A = A, T = T, pivots = pivots, rank = rank, basis = basis }
    cache[n] = prep
    return prep
end

-- Dimension of the null space: how many independent "do nothing" press sets.
function GF2.nullity(n)
    return #prepare(n).basis
end

-- Press vector that toggles exactly the cells in b (flat 0/1), with the
-- fewest presses. Returns x (flat 0/1) and its weight, or nil when b is not
-- reachable (impossible for boards built by pressing from all-off).
function GF2.solve(n, b)
    local P = prepare(n)
    local N = P.N
    -- Apply the recorded row operations: c = T·b.
    local c = {}
    for i = 1, N do
        local s, ti = 0, P.T[i]
        for j = 1, N do
            if ti[j] == 1 and b[j] == 1 then s = s + 1 end
        end
        c[i] = s % 2
    end
    -- Rows past the rank read 0 = c[i]; a 1 there means no solution.
    for i = P.rank + 1, N do
        if c[i] == 1 then return nil end
    end
    local x = {}
    for j = 1, N do x[j] = 0 end
    for k = 1, P.rank do x[P.pivots[k]] = c[k] end

    -- Fewest presses: try every combination of null-space vectors. Ties go
    -- to the first combination found, so the answer is deterministic.
    local basis = P.basis
    local best, best_w = x, nil
    for mask = 0, 2 ^ #basis - 1 do
        local y, m = {}, mask
        for j = 1, N do y[j] = x[j] end
        for k = 1, #basis do
            if m % 2 == 1 then
                local v = basis[k]
                for j = 1, N do
                    if v[j] == 1 then y[j] = 1 - y[j] end
                end
            end
            m = math.floor(m / 2)
        end
        local w = 0
        for j = 1, N do w = w + y[j] end
        if not best_w or w < best_w then best, best_w = y, w end
    end
    return best, best_w
end

-- Is the flat 0/1 board b solvable at all?
function GF2.solvable(n, b)
    return GF2.solve(n, b) ~= nil
end

return GF2
