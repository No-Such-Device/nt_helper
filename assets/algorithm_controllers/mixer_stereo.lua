local function display_value(parameter)
  if parameter == nil then return "" end
  if parameter.display_value ~= nil and parameter.display_value ~= "" then
    return parameter.display_value
  end
  local enum = parameter.enum_values[parameter.value + 1]
  if enum ~= nil and enum ~= "" then return enum end

  local value = parameter.value
  local decimals = 0
  if parameter.power_of_ten ~= nil and parameter.power_of_ten < 0 then
    decimals = -parameter.power_of_ten
    value = value * (10 ^ parameter.power_of_ten)
  end
  local text = decimals > 0 and
    string.format("%." .. decimals .. "f", value) or tostring(value)
  if parameter.unit ~= nil and parameter.unit ~= "" then
    return text .. " " .. parameter.unit
  end
  return text
end

local channels = {}
for _, channel in ipairs(nt.channels()) do
  if nt.channel_parameter(channel, "Gain") ~= nil and
      nt.channel_parameter(channel, "Pan") ~= nil then
    table.insert(channels, channel)
  end
end

local sends = {}
for send = 1, 4 do
  if nt.parameter(send .. ":Destination") ~= nil then
    table.insert(sends, send)
  end
end

local function mixer_shapes()
  local shapes = {
    ui.rect {
      x = 0,
      y = 0.04,
      width = 1,
      height = 0.92,
      radius = 0.08,
      fill = "surface_container_highest"
    },
    ui.line {
      x1 = 0.04,
      y1 = 0.84,
      x2 = 0.96,
      y2 = 0.84,
      stroke = "outline"
    }
  }

  local count = #channels
  for index, channel in ipairs(channels) do
    local gain = nt.channel_parameter(channel, "Gain")
    local pan = nt.channel_parameter(channel, "Pan")
    local mute = nt.channel_parameter(channel, "Mute")
    local solo = nt.channel_parameter(channel, "Solo")
    local x = 0.05 + ((index - 0.5) / count) * 0.9
    local cell_width = 0.82 / count
    local gain_range = math.max(1, gain.maximum - gain.minimum)
    local level = math.max(
      0,
      math.min(1, (gain.value - gain.minimum) / gain_range)
    )
    local top = 0.84 - level * 0.58
    local muted = mute ~= nil and mute.value ~= 0
    local soloed = solo ~= nil and solo.value ~= 0
    local color = muted and "outline" or (soloed and "tertiary" or "primary")

    table.insert(shapes, ui.line {
      x1 = x,
      y1 = 0.2,
      x2 = x,
      y2 = 0.84,
      stroke = "outline"
    })
    table.insert(shapes, ui.rect {
      x = x - math.min(0.025, cell_width * 0.28),
      y = top,
      width = math.min(0.05, cell_width * 0.56),
      height = 0.84 - top,
      radius = 0.01,
      fill = color
    })

    local pan_position = math.max(-1, math.min(1, pan.value / 100))
    local pan_half_width = math.min(0.035, cell_width * 0.38)
    table.insert(shapes, ui.line {
      x1 = x - pan_half_width,
      y1 = 0.13,
      x2 = x + pan_half_width,
      y2 = 0.13,
      stroke = "outline"
    })
    table.insert(shapes, ui.circle {
      x = x + pan_position * pan_half_width,
      y = 0.13,
      radius = math.min(0.018, cell_width * 0.18),
      fill = color,
      stroke = color
    })
  end
  return shapes
end

local function mixer_semantics()
  local descriptions = {}
  for _, channel in ipairs(channels) do
    local gain = nt.channel_parameter(channel, "Gain")
    local pan = nt.channel_parameter(channel, "Pan")
    local mute = nt.channel_parameter(channel, "Mute")
    local solo = nt.channel_parameter(channel, "Solo")
    local state = ""
    if mute ~= nil and mute.value ~= 0 then state = ", muted" end
    if solo ~= nil and solo.value ~= 0 then state = state .. ", soloed" end
    table.insert(
      descriptions,
      "channel " .. channel .. " gain " .. display_value(gain) ..
        ", pan " .. display_value(pan) .. state
    )
  end
  return "Illustrative mixer control overview: " ..
    table.concat(descriptions, "; ") ..
    ". Bars represent configured gains and dots represent configured pan " ..
    "positions; this is not a live level meter."
end

local root_children = {}
local output_gain = nt.parameter("Output gain")
if output_gain ~= nil then
  table.insert(root_children, ui.section {
    title = "Main mix",
    subtitle = #channels .. " channels · " .. #sends .. " aux sends · " ..
      display_value(output_gain),
    children = {
      ui.slider {
        label = "Output gain",
        parameter = output_gain.number
      }
    }
  })
end

if #channels > 0 then
  table.insert(root_children, ui.canvas {
    semantics_label = mixer_semantics(),
    aspect_ratio = 5.5,
    shapes = mixer_shapes()
  })
end

if #sends > 0 then
  local send_children = {}
  for _, send in ipairs(sends) do
    local pre_post = nt.parameter(send .. ":Pre/post")
    local width = nt.parameter(send .. ":Width")
    if pre_post ~= nil then
      table.insert(send_children, ui.choice {
        label = "Send " .. send .. " timing",
        parameter = pre_post.number
      })
    end
    if width ~= nil then
      table.insert(send_children, ui.choice {
        label = "Send " .. send .. " width",
        parameter = width.number
      })
    end
  end
  table.insert(root_children, ui.section {
    title = "Aux sends",
    subtitle = #sends .. " configured",
    children = send_children
  })
end

for _, channel in ipairs(channels) do
  local gain = nt.channel_parameter(channel, "Gain")
  local pan = nt.channel_parameter(channel, "Pan")
  local mute = nt.channel_parameter(channel, "Mute")
  local solo = nt.channel_parameter(channel, "Solo")
  local name = nt.channel_parameter(channel, "Name")
  local children = {
    ui.slider {
      label = "Gain",
      parameter = gain.number
    },
    ui.slider {
      label = "Pan",
      parameter = pan.number
    }
  }

  if mute ~= nil then
    table.insert(children, ui.toggle {
      label = "Mute",
      parameter = mute.number
    })
  end
  if solo ~= nil then
    table.insert(children, ui.toggle {
      label = "Solo",
      parameter = solo.number
    })
  end
  for _, send in ipairs(sends) do
    local send_gain = nt.channel_parameter(channel, send .. ":Send gain")
    if send_gain ~= nil then
      table.insert(children, ui.slider {
        label = "Send " .. send,
        parameter = send_gain.number
      })
    end
  end

  local title = "Channel " .. channel
  if name ~= nil and name.display_value ~= nil and name.display_value ~= "" then
    title = title .. " · " .. name.display_value
  end
  local state = ""
  if mute ~= nil and mute.value ~= 0 then state = " · muted" end
  if solo ~= nil and solo.value ~= 0 then state = state .. " · soloed" end
  table.insert(root_children, ui.section {
    title = title,
    subtitle = display_value(gain) .. " · pan " .. display_value(pan) .. state,
    children = children
  })
end

if #channels == 0 then
  table.insert(root_children, ui.text {
    text = "No stereo mixer channels were found in this slot.",
    style = "body"
  })
end

return {
  version = 1,
  title = "Mixer Stereo",
  root = ui.column {
    gap = 16,
    padding = 16,
    children = root_children
  }
}
