local nk = require("nakama") 

assert(nk, "Nakama module not found")

local TTT_MATCH_MODULE = "tiktaktoe" 
local TTT_MATCH_NAME = "tik-tak-toe" 

-- op codes 
local OP_MOVE = 1 
local OP_STATE = 2 
local OP_ERROR = 3 
local OP_RESTART = 4

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
        symbols = state.symbols }) 
end 

local function broadcast_state(dispatcher, state) 
    dispatcher.broadcast_message(OP_STATE, snapshot(state)) 
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
        status = "waiting", 
        winner = nil } 
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
        if not state.players_by_id[presence.user_id] then 
            table.insert(state.players, presence) 
            state.players_by_id[presence.user_id] = presence 
        end 
    end 
    if #state.players == 2 and state.status == "waiting" then 
        -- initilize a fresh board and assign symbols based on join order. 
        state.board = {"","","","","","","","",""} 
        local p1 = state.players[1].user_id 
        local p2 = state.players[2].user_id 
        state.symbols[p1] = "X" 
        state.symbols[p2] = "O" 
        state.turn = p1 
        state.status = "playing" 
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
    if state.status == "playing" and #state.players == 1 then 
        state.status = "ended" 
        state.winner = state.players[1].user_id
    elseif #state.players == 0 then 
        state.status = "ended" 
    end 
    for _, presence in ipairs(presences) do 
        state.players_by_id[presence.user_id] = nil 
        state.symbols[presence.user_id] = nil 
    end 
    if state.status == "ended" then
        state.turn = nil
    end 
    broadcast_state(dispatcher, state) 
    return state 
end 

local function processMove(message, dispatcher, state)
    local player_id = message.sender.user_id 

    if player_id ~= state.turn then 
        dispatcher.broadcast_message(OP_ERROR, nk.json_encode({msg = "Not your turn"}), {message.sender}) 
        return  
    end 

    --making sure player is actually one of the 2 added players 
    local symbol = state.symbols[player_id] 
    if not symbol then 
        dispatcher.broadcast_message(OP_ERROR, nk.json_encode({msg="Not a player in this match"}), {message.sender}) 
        return
    end
    local ok, move = pcall(nk.json_decode, message.data) 
    if not ok or type(move) ~= "table" or type(move.cell) ~= "number" then 
        dispatcher.broadcast_message(OP_ERROR, nk.json_encode({msg="Bad payload"}), {message.sender}) 
        return
    end 
    
    local cell = move.cell 
    if cell < 1 or cell > 9 or state.board[cell] ~= "" then 
        dispatcher.broadcast_message(OP_ERROR, nk.json_encode({msg="invalid cell"}), {message.sender}) 
        return
    end 
    
    state.board[cell] = symbol 
    
    local won, _ = check_win(state.board) 
    if won then 
        state.status = "ended" 
        state.winner = player_id 
    elseif check_draw(state.board) then 
        state.status = "ended" 
        state.winner = nil 
    else 
        -- switch turns 
        if state.turn == state.players[1].user_id then 
            state.turn = state.players[2].user_id 
        else 
            state.turn = state.players[1].user_id 
        end 
    end 
    broadcast_state(dispatcher, state)
end

local function reset_game(state) 
    state.board = {"","","","","","","","",""}
    state.status = "playing"
    state.winner = nil
    -- alternate who starts this round:
    if state.players[1] and state.players[2] then
        if state.turn == state.players[1].user_id then
            state.turn = state.players[2].user_id
        else
            state.turn = state.players[1].user_id
        end
    end
end

function M.match_loop(context, dispatcher, tick, state, messages) 
    for _, message in ipairs(messages) do 
        if message.op_code == OP_MOVE and state.status == "playing" then 
            processMove(message, dispatcher, state) 
        elseif message.op_code == OP_RESTART and state.status == "ended" then
            --only current players can restart
            local pid = message.sender.user_id
            if state.symbols[pid] then
                reset_game(state)
                broadcast_state(dispatcher, state)
            else
                dispatcher.broadcast_message(OP_ERROR, nk.json_encode({msg="Not a player in this match"}), {message.sender})
            end
        end 
    end 
    return state 
end 

function M.match_terminate(context, dispatcher, tick, state, grace_seconds) 
    return nil 
end

return M