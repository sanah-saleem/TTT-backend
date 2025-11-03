local nk = require("nakama") 

local TTT_MATCH_MODULE = "tiktaktoe"

local function rpc_create_match(context, payload) 
    local match_id, err = nk.match_create(TTT_MATCH_MODULE, {}) 
    if not match_id then 
        return nk.json_encode({ error = "Failed to create match: " .. tostring(err) }) 
    end 
    return nk.json_encode({ match_id = match_id }) 
end 
nk.register_rpc(rpc_create_match, "create_match") 

local function rpc_auto_pairing(context, matched_users) 
    local match_id, err = nk.match_create(TTT_MATCH_MODULE, {}) 
    if not match_id then 
        nk.logger_error("Could not create match: " .. tostring(err)) 
        return nil 
    end 
    return match_id 
end 
nk.register_matchmaker_matched(rpc_auto_pairing)