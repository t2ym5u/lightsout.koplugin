local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase           = require("screen_base")
local MenuHelper           = require("menu_helper")
local LightsOutBoard       = lrequire("board")
local LightsOutBoardWidget = lrequire("board_widget")

local GAME_RULES_EN = _([[
Lights Out — Rules

Switch every light off.

Tapping a cell switches it and its four neighbours (above, below, left and right): lit cells go dark, dark cells light up. Lit cells are black.

Every puzzle can be solved. The status line shows the optimal number of presses for this board; pressing a cell twice does nothing, and the order of presses never matters.

Hint shows a cell to press next on an optimal path. Show solution marks every cell of that path with a ring.
]])

local GAME_RULES_FR = [[
Lights Out — Règles

Éteignez toutes les lumières.

Toucher une case l'inverse, ainsi que ses quatre voisines (au-dessus, en dessous, à gauche et à droite) : les cases allumées s'éteignent, les cases éteintes s'allument. Les cases allumées sont noires.

Chaque puzzle a une solution. La ligne d'état indique le nombre optimal d'appuis pour cette grille ; appuyer deux fois sur une case ne change rien, et l'ordre des appuis n'a pas d'importance.

Astuce indique une case à toucher sur un chemin optimal. Voir la solution marque d'un cercle chaque case de ce chemin.
]]

local LightsOutScreen = ScreenBase:extend{}

-- A hint here is a press, not a value to fill in.
function LightsOutScreen:describeHintStep(step, level)
    if level == 1 then
        return T(_("Press R%1C%2 next. Tap Hint again to press it."), step.r, step.c)
    end
    return T(_("Pressed R%1C%2."), step.r, step.c)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function LightsOutScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n", LightsOutBoard.DEFAULT_N)
    self.board  = LightsOutBoard:new{ n = n }
    if not self.board:load(state) then
        self.board:generate(self.plugin:getSetting("difficulty", "easy"))
    end
    ScreenBase.init(self)
end

function LightsOutScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function LightsOutScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Lights Out"), function()
        return {
            { text = _("New game"),              callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = self:getSizeButtonText(),   callback = function() self:openSizeMenu() end },
            { text = self:getDiffButtonText(),   callback = function() self:openDifficultyMenu() end },
            { text = self:getRevealButtonText(), callback = function() self:toggleSolution() end },
            { text = _("Restart"),               callback = function() self:onRestart() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local action_bar = self:buildActionBar({
        { text = _("Hint"), callback = function() self:onHint() end },
        { id = "undo_button", text = _("Undo"), callback = function() self:onUndo() end },
    })
    self.undo_button = action_bar:getButtonById("undo_button")
    self:updateUndoButton()
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        action_bar,
    }

    local frame_pad   = Size.padding.large
    local frame_extra = 2 * (frame_pad + Size.border.window)
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = LightsOutBoardWidget:new{
        board        = self.board,
        max_size     = math.min(budget_w, budget_h) - frame_extra,
        onCellAction = function(r, c) self:onCellAction(r, c) end,
    }
    local board_frame = FrameContainer:new{
        padding = frame_pad,
        margin  = 0,
        self.board_widget,
    }

    if is_landscape then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Cell interaction
-- ---------------------------------------------------------------------------

function LightsOutScreen:onCellAction(r, c)
    if not self.board:press(r, c) then return end
    self.hint_cell = nil
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:updateUndoButton()
    if self.board:isSolved() then self:recordWin() end
    self:updateStatus()
end

function LightsOutScreen:isRoundOver()
    return self.board:isSolved()
end

-- Fewest moves per size, only for rounds played without hints.
function LightsOutScreen:bestKey()
    return "best_moves_" .. self.board.n .. "_" .. self.board.difficulty
end

function LightsOutScreen:recordWin()
    if self.board:getHintsUsed() > 0 then return end
    local best = self.plugin:getSetting(self:bestKey())
    if not best or self.board.moves < best then
        self.plugin:saveSetting(self:bestKey(), self.board.moves)
    end
end

-- ---------------------------------------------------------------------------
-- Game actions
-- ---------------------------------------------------------------------------

function LightsOutScreen:onNewGame()
    local diff = self.plugin:getSetting("difficulty", "easy")
    local n    = self.plugin:getSetting("grid_n", LightsOutBoard.DEFAULT_N)
    self.board = LightsOutBoard:new{ n = n }
    self.board:generate(diff)
    self.hint_cell = nil
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function LightsOutScreen:onRestart()
    self.board:restart()
    self.hint_cell = nil
    self.plugin:saveState(self.board:serialize())
    self.board_widget:refresh()
    self:updateUndoButton()
    self:updateStatus()
end

function LightsOutScreen:onUndo()
    if not self.board:undo() then
        self:updateStatus(_("Nothing to undo."))
        return
    end
    self.hint_cell = nil
    self.plugin:saveState(self.board:serialize())
    self.board_widget:refresh()
    self:updateUndoButton()
    self:updateStatus(_("Last move undone."))
end

function LightsOutScreen:onHint()
    ScreenBase.onHint(self)
    self:updateUndoButton()
end

-- The rings follow the board as it changes, so play stays enabled while
-- they are shown.
function LightsOutScreen:toggleSolution()
    self.board:toggleSolution()
    self.hint_cell = nil
    self.board_widget:refresh()
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function LightsOutScreen:openSizeMenu()
    local sizes = {}
    for _, n in ipairs(LightsOutBoard.SIZES) do
        sizes[#sizes + 1] = { id = n, text = n .. "\xC3\x97" .. n }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select size"),
        sizes     = sizes,
        current   = self.board.n,
        parent    = self,
        on_select = function(n)
            self.plugin:saveSetting("grid_n", n)
            self:onNewGame()
        end,
    }
end

function LightsOutScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "easy"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            self:onNewGame()
        end,
    }
end

-- ---------------------------------------------------------------------------
-- Status / button text
-- ---------------------------------------------------------------------------

function LightsOutScreen:getSizeButtonText()
    return T(_("Size: %1"), T("%1×%1", self.board.n))
end

function LightsOutScreen:getDiffLabel()
    local diff = self.board.difficulty
    return MenuHelper.DIFFICULTY_LABELS[diff] or diff
end

function LightsOutScreen:getDiffButtonText()
    return T(_("Difficulty: %1"), self:getDiffLabel())
end

function LightsOutScreen:getRevealButtonText()
    return self.board:isShowingSolution() and _("Hide solution") or _("Show solution")
end

function LightsOutScreen:updateStatus(msg)
    local status
    local board = self.board
    if msg then
        status = msg
    elseif board:isSolved() then
        local best = self.plugin:getSetting(self:bestKey())
        status = self:joinStatus(
            T(_("All lights out in %1 moves!"), board.moves),
            T(_("Optimal: %1"), board.par),
            best and T(_("Best: %1"), best))
    else
        -- While the rings are shown, how many are left says more than the
        -- difficulty does, and the line has to stay on one row.
        local _plan, left = board:getPlan()
        status = self:joinStatus(
            T("%1×%1", board.n),
            not board:isShowingSolution() and self:getDiffLabel() or nil,
            T(_("Moves: %1"), board.moves),
            T(_("Optimal: %1"), board.par),
            board:isShowingSolution() and T(_("Presses left: %1"), left) or nil)
    end
    ScreenBase.updateStatus(self, status)
    self:refreshActionBar()
end

function LightsOutScreen:updateUndoButton()
    if not self.undo_button then return end
    self.undo_button:enableDisable(self.board:canUndo())
end

return LightsOutScreen
