local Blitbuffer = require("ffi/blitbuffer")
local common     = require("grid_widget_base")

local GridWidgetBase = common.GridWidgetBase
local drawLine       = common.drawLine

local C_BG     = Blitbuffer.COLOR_WHITE
local C_ON     = Blitbuffer.COLOR_BLACK
local C_OFF    = Blitbuffer.COLOR_GRAY_E
local C_EDGE   = Blitbuffer.COLOR_GRAY_9
local C_INK    = Blitbuffer.COLOR_BLACK

-- ---------------------------------------------------------------------------
-- LightsOutBoardWidget — one square button per cell.
--
-- A lit cell is solid black, a dark one pale grey with a grey edge: the
-- strongest contrast e-ink has, so the board reads at a glance. "Show
-- solution" puts a ring on each cell of the optimal plan (white on a lit
-- cell, black on a dark one); the hint target gets a heavy frame.
-- ---------------------------------------------------------------------------

local LightsOutBoardWidget = GridWidgetBase:extend{
    board = nil,
}

function LightsOutBoardWidget:init()
    self.cols = self.board and self.board.n or 5
    self.rows = self.cols
    GridWidgetBase.init(self)
end

function LightsOutBoardWidget:onCellTap(row, col)
    if self.onCellAction then self.onCellAction(row, col) end
end

local function frame(bb, x, y, w, h, t, color)
    drawLine(bb, x, y, w, t, color)
    drawLine(bb, x, y + h - t, w, t, color)
    drawLine(bb, x, y, t, h, color)
    drawLine(bb, x + w - t, y, t, h, color)
end

function LightsOutBoardWidget:paintTo(bb, x, y)
    local rect = self.paint_rect
    rect.x, rect.y = x, y
    local board = self.board
    local n     = board.n
    local cell  = self.cell_w
    local gap   = math.max(3, math.floor(cell * 0.07))
    local plan  = board:isShowingSolution() and board:getPlan() or nil

    bb:paintRect(x, y, rect.w, rect.h, C_BG)

    for r = 1, n do
        for c = 1, n do
            local x0 = x + math.floor((c - 1) * cell) + gap
            local y0 = y + math.floor((r - 1) * cell) + gap
            local s  = math.floor(c * cell) - math.floor((c - 1) * cell) - 2 * gap
            local lit = board.lights[r][c]
            if lit then
                bb:paintRect(x0, y0, s, s, C_ON)
            else
                bb:paintRect(x0, y0, s, s, C_OFF)
                frame(bb, x0, y0, s, s, math.max(1, math.floor(gap / 2)), C_EDGE)
            end
            if plan and plan[r][c] then
                local rad = math.floor(s * 0.22)
                local cx, cy = x0 + math.floor(s / 2), y0 + math.floor(s / 2)
                local ring = lit and C_BG or C_INK
                bb:paintCircle(cx, cy, rad, ring, math.max(3, math.floor(rad / 3)))
            end
        end
    end

    local sel = board.selected
    if sel then
        local x0 = x + math.floor((sel.c - 1) * cell)
        local y0 = y + math.floor((sel.r - 1) * cell)
        local s  = math.floor(sel.c * cell) - math.floor((sel.c - 1) * cell)
        -- Black frame in the gap around the cell, plus a second frame inside
        -- it in the contrasting colour: on a lit (black) cell the outer one
        -- alone would just look like a bigger black square.
        frame(bb, x0, y0, s, s, gap, C_INK)
        local inset = 2 * gap
        local inner = board.lights[sel.r][sel.c] and C_BG or C_INK
        frame(bb, x0 + inset, y0 + inset, s - 2 * inset, s - 2 * inset, gap, inner)
    end
end

return LightsOutBoardWidget
