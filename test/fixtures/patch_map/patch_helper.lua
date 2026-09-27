-- NT Helper companion, executed on the computer, NOT a disting NT Lua algorithm.
-- Install as /helper/ThPh.lua on the NT SD card.
local models = { 'NTX-8CV', 'ES-5', 'ESX-8GT', 'ESX-8CV' }
return {
  api_version = 1,
  guid = 'ThPh',
  render = function(state)
    local groups = {
      { title = 'Inputs', short = 'Inputs', start = 0, count = 12, columns = 4 },
      { title = 'Outputs', short = 'Outputs', start = 12, count = 8, columns = 2 },
    }
    for i, expander in ipairs(state.expanders) do
      groups[#groups + 1] = {
        title = expander.name .. ' · ' .. models[expander.type + 1],
        short = 'E' .. i, start = 20 + (i - 1) * 8, count = 8, columns = 1,
      }
    end
    return {
      version = 1, type = 'socket_table', groups = groups,
      labels = { socket = 'Socket', destination = 'Destination', colour = 'Cable colour', tag = 'Tag', group = 'Group' },
    }
  end,
  handle = function(state, event)
    -- Emit declarative requests. Only the host validates and sends writes;
    -- state is an immutable snapshot of the last NT acknowledgement.
    if event.type == 'set_connection' then
      return { type = 'set_connection', connection = event.connection }
    elseif event.type == 'set_title' then
      return { type = 'set_title', title = event.title }
    elseif event.type == 'add_expander' then
      return { type = 'add_expander', model = event.model }
    elseif event.type == 'rename_expander' then
      return { type = 'rename_expander', index = event.index, name = event.name }
    elseif event.type == 'move_expander' then
      return { type = 'move_expander', from = event.from, to = event.to }
    end
    error('Unsupported editor action')
  end,
}
