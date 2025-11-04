local nk = require("nakama") 

assert(nk, "Nakama module not found")

local TTT_MATCH_MODULE = "tiktaktoe" 
local TTT_MATCH_NAME = "tik-tak-toe" 

-- op codes 
local OP_MOVE = 1 
local OP_STATE = 2 
local OP_ERROR = 3 
local OP_RESTART = 4

local STATUS_WAITING = "waiting"
local STATUS_PLAYING = "playing"
local STATUS_ENDED   = "ended"

local function check_win(board) 
    local win_positions = {
        {1,2,3},{4,5,6},{7,8,9}, -- rows 
        {1,4,7},{2,5,8},{3,6,9}, -- cols 
        {1,5,9},{3,5,7} -- diagonals 
    } 
    for _, pos in ipairs(win_positions) do 
        local a, b, c = pos[1], pos[2], pos[3] 
        if board[a] ~= "" and board[a] == board[b] and board[b] == board[c] then 
            return true, board[a] 
        end 
    end 
    return false, nil 
end 
    
local function check_draw(board) 
    for i = 1, 9 do 
        if board[i] == "" then 
            return false 
        end 
    end 
    return true 
end 

local function snapshot(state) 
    return nk.json_encode({ 
        board = state.board, 
        turn = state.turn, -- user_id whose turn it is 
        status = state.status, -- "waiting" | "playing" | "ended" 
        winner = state.winner, -- user_id or nil 
        players = { state.players[1] and state.players[1].user_id or nil, 
                    state.players[2] and state.players[2].user_id or nil 
                }, 
        symbols = state.symbols,
        turnDeadlineMs = state.turn_deadline_ms, }) 
end 

local function broadcast_state(dispatcher, state) 
    dispatcher.broadcast_message(OP_STATE, snapshot(state)) 
end 

local function broadcast_error(dispatcher, msg, recipients)
    recipients = recipients or nil  -- nil = broadcast to all
    dispatcher.broadcast_message(OP_ERROR, nk.json_encode({ msg = msg }), recipients)
end

local TURN_MS = 15000 -- 15 secs per turn

local function other_player_id(state, pid)
    if not state.players[1] or not state.players[2] then return nil end
    return (state.players[1].user_id == pid) and state.players[2].user_id or state.players[1].user_id
end

-- Module table to avoid forward-ref issues.
local M = {}

function M.match_init(context, params) 
    local state = { 
        board = {"","","","","","","","",""}, 
        players = {}, -- players in insertion order 
        players_by_id = {}, -- players in the order of id 
        symbols = {}, 
        turn = nil, 
        status = STATUS_WAITING, 
        winner = nil,
        turn_deadline_ms = nil, } 
    local tick_rate = 2 
    local label = nk.json_encode({
                        properties = { module = TTT_MATCH_MODULE },
                        name = TTT_MATCH_NAME
                    })
    return state, tick_rate, label 
end 

function M.match_join_attempt(context, dispatcher, tick, state, presence, metadata) 
    if #state.players >= 2 then 
        return state, false, "room full" 
    end 
    if state.players_by_id[presence.user_id] then 
        return state, false, "already joined" 
    end 
    return state, true 
end 

function M.match_signal(context, dispatcher, tick, state, data) 
    -- Return the current state and optionally some response data.
    -- Since you are not using signals, we just return the state unchanged.
    return state, nil 
end

function M.match_join(context, dispatcher, tick, state, presences) 
    for _, presence in ipairs(presences) do 
        if not presence or presence.user_id then
            nk.logger_warn("Invalid presence during join attempt")
            return state, false, "invalid presence"
        end

        if not state.players_by_id[presence.user_id] then 
            table.insert(state.players, presence) 
            state.players_by_id[presence.user_id] = presence 
        end 
    end 
    if #state.players == 2 and state.status == STATUS_WAITING then 
        -- initilize a fresh board and assign symbols based on join order. 
        state.board = {"","","","","","","","",""} 
        local p1 = state.players[1].user_id 
        local p2 = state.players[2].user_id 
        state.symbols[p1] = "X" 
        state.symbols[p2] = "O" 
        state.turn = p1 
        state.status = STATUS_PLAYING
        state.turn_deadline_ms = nk.time() + TURN_MS 
    end 
    broadcast_state(dispatcher, state) 
    return state 
end 

function M.match_leave(context, dispatcher, tick, state, presences) 
    -- If someone leaves mid-game, end the match and set winner to the other player. 
    local leaving = {} 
    for _, presence in ipairs(presences) do 
        leaving[presence.user_id] = true 
    end 
    local remaining = {} 
    for _, p in ipairs(state.players) do 
        if not leaving[p.user_id] then 
            table.insert(remaining, p) 
        end 
    end 
    state.players = remaining 
    if state.status == STATUS_PLAYING and #state.players == 1 then 
        state.status = STATUS_ENDED 
        state.winner = state.players[1].user_id
    elseif #state.players == 0 then 
        state.status = STATUS_ENDED 
        state.winner = nil
    end 
    for _, presence in ipairs(presences) do 
        state.players_by_id[presence.user_id] = nil 
        state.symbols[presence.user_id] = nil 
    end 
    if state.status == STATUS_ENDED then
        state.turn = nil
        state.turn_deadline_ms = nil
    end 
    broadcast_state(dispatcher, state) 
    return state 
end 

local function processMove(message, dispatcher, state)
    local player_id = message.sender.user_id 

    if player_id ~= state.turn then 
        broadcast_error(dispatcher, "Not your turn", {message.sender})
        return  
    end 

    --making sure player is actually one of the 2 added players 
    local symbol = state.symbols[player_id] 
    if not symbol then 
        broadcast_error(dispatcher, "Not a player in this match", {message.sender})
        return
    end
    local ok, move = pcall(nk.json_decode, message.data) 
    if not ok or type(move) ~= "table" or type(move.cell) ~= "number" then 
        broadcast_error(dispatcher, "Bad payload", {message.sender})
        return
    end 
    
    local cell = move.cell 
    if cell < 1 or cell > 9 or state.board[cell] ~= "" then 
        broadcast_error(dispatcher, "invalid cell", {message.sender})
        return
    end 
    
    state.board[cell] = symbol 
    
    local won, _ = check_win(state.board) 
    if won then 
        state.status = STATUS_ENDED 
        state.winner = player_id 
    elseif check_draw(state.board) then 
        state.status = STATUS_ENDED 
        state.winner = nil 
    else 
        -- switch turns 
        if state.turn == state.players[1].user_id then 
            state.turn = state.players[2].user_id 
        else 
            state.turn = state.players[1].user_id 
        end 
        state.turn_deadline_ms = nk.time() + TURN_MS
    end 
    broadcast_state(dispatcher, state)
end

local function reset_game(state) 
    state.board = {"","","","","","","","",""}
    state.status = STATUS_PLAYING
    state.winner = nil
    -- alternate who starts this round:
    if state.players[1] and state.players[2] then
        if state.turn == state.players[1].user_id then
            state.turn = state.players[2].user_id
        else
            state.turn = state.players[1].user_id
        end
    end
    state.turn_deadline_ms = nk.time() + TURN_MS
end

function M.match_loop(context, dispatcher, tick, state, messages) 
    --enforce timer
    if state.status == STATUS_PLAYING and state.turn and state.turn_deadline_ms then
        if nk.time() >= state.turn_deadline_ms then
            local winner = other_player_id(state, state.turn)
            state.status = STATUS_ENDED
            state.winner = winner
            state.turn = nil
            state.turn_deadline_ms = nil
            broadcast_state(dispatcher, state)
            return state
        end
    end
    for _, message in ipairs(messages) do 
        if message.op_code == OP_MOVE and state.status == STATUS_PLAYING then 
            processMove(message, dispatcher, state) 
        elseif message.op_code == OP_RESTART and state.status == STATUS_ENDED then
            if #state.players < 2 then 
                broadcast_error(dispatcher, "Cannot restart without both players", {message.sender})
            end
            --only current players can restart
            local pid = message.sender.user_id
            if state.symbols[pid] then
                reset_game(state)
                broadcast_state(dispatcher, state)
            else
                broadcast_error(dispatcher, "Not a player in this match", {message.sender})
            end
        end 
    end 
    if state.status == STATUS_ENDED and #state.players == 0 then
        nk.match_terminate(context.match_id)
    end
    return state 
end 

function M.match_terminate(context, dispatcher, tick, state, grace_seconds) 
    nk.logger_info(("Match %s terminated."):format(context.match_id))
    return nil 
end

return M