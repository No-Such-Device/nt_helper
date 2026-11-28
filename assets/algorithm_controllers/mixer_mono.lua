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
      nt.channel_parameter(channel, "Mute") ~= nil and
      nt.channel_parameter(channel, "Solo") ~= nil then
    table.insert(channels, channel)
  end
end

-- Infer configured sends from their behavioral parameter. Do not inspect or
-- expose the send destination, which belongs to routing.
local sends = {}
for send = 1, 4 do
  if nt.parameter(send .. ":Pre/post") ~= nil then
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
      y1 = 0.86,
      x2 = 0.96,
      y2 = 0.86,
      stroke = "outline"
    }
  }

  local count = #channels
  for index, channel in ipairs(channels) do
    local gain = nt.channel_parameter(channel, "Gain")
    local mute = nt.channel_parameter(channel, "Mute")
    local solo = nt.channel_parameter(channel, "Solo")
    local x = 0.05 + ((index - 0.5) / count) * 0.9
    local cell_width = 0.82 / count
    local gain_range = math.max(1, gain.maximum - gain.minimum)
    local level = math.max(
      0,
      math.min(1, (gain.value - gain.minimum) / gain_range)
    )
    local top = 0.86 - level * 0.68
    local muted = mute ~= nil and mute.value ~= 0
    local soloed = solo ~= nil and solo.value ~= 0
    local color = muted and "outline" or (soloed and "tertiary" or "primary")

    table.insert(shapes, ui.line {
      x1 = x,
      y1 = 0.14,
      x2 = x,
      y2 = 0.86,
      stroke = "outline"
    })
    table.insert(shapes, ui.rect {
      x = x - math.min(0.027, cell_width * 0.3),
      y = top,
      width = math.min(0.054, cell_width * 0.6),
      height = 0.86 - top,
      radius = 0.01,
      fill = color
    })
  end
  return shapes
end

local function mixer_semantics()
  local descriptions = {}
  for _, channel in ipairs(channels) do
    local gain = nt.channel_parameter(channel, "Gain")
    local mute = nt.channel_parameter(channel, "Mute")
    local solo = nt.channel_parameter(channel, "Solo")
    local state = ""
    if mute ~= nil and mute.value ~= 0 then state = ", muted" end
    if solo ~= nil and solo.value ~= 0 then state = state .. ", soloed" end
    table.insert(
      descriptions,
      "channel " .. channel .. " gain " .. display_value(gain) .. state
    )
  end
  return "Configured mono mixer gain overview: " ..
    table.concat(descriptions, "; ") ..
    ". Bars represent configured gains and are not live signal meters."
end

local root_children = {}
local output_gain = nt.parameter("Output gain")
local main_children = {}
if output_gain ~= nil then
  table.insert(main_children, ui.slider {
    label = "Output gain",
    parameter = output_gain.number
  })
end

if #channels > 0 then
  table.insert(main_children, ui.canvas {
    semantics_label = mixer_semantics(),
    aspect_ratio = 5.5,
    shapes = mixer_shapes()
  })
  table.insert(main_children, ui.text {
    text = "Configured gain, mute, and solo state — not live audio levels.",
    style = "caption"
  })
end

if #main_children > 0 then
  local main_subtitle =
    #channels .. " channels · " .. #sends .. " aux sends"
  if output_gain ~= nil then
    main_subtitle = main_subtitle .. " · " .. display_value(output_gain)
  end
  table.insert(root_children, ui.section {
    title = "Main mix",
    subtitle = main_subtitle,
    children = main_children
  })
end

local send_children = {}
for _, send in ipairs(sends) do
  local pre_post = nt.parameter(send .. ":Pre/post")
  if pre_post ~= nil then
    table.insert(send_children, ui.choice {
      label = "Send " .. send .. " timing",
      parameter = pre_post.number
    })
  end
end
if #send_children == 0 then
  table.insert(send_children, ui.text {
    text = "No aux sends are configured for this slot.",
    style = "caption"
  })
end
table.insert(root_children, ui.section {
  title = "Aux sends",
  subtitle = #sends == 0 and "None configured" or #sends .. " configured",
  children = send_children
})

for _, channel in ipairs(channels) do
  local gain = nt.channel_parameter(channel, "Gain")
  local mute = nt.channel_parameter(channel, "Mute")
  local solo = nt.channel_parameter(channel, "Solo")
  local name = nt.channel_parameter(channel, "Name")
  local children = {
    ui.slider {
      label = "Gain",
      parameter = gain.number
    },
    ui.toggle {
      label = "Mute",
      parameter = mute.number
    },
    ui.toggle {
      label = "Solo",
      parameter = solo.number
    }
  }

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
  if mute.value ~= 0 then state = " · muted" end
  if solo.value ~= 0 then state = state .. " · soloed" end
  table.insert(root_children, ui.section {
    title = title,
    subtitle = display_value(gain) .. state,
    children = children
  })
end

if #channels == 0 then
  table.insert(root_children, ui.text {
    text = "No mono mixer channels were found in this slot.",
    style = "body"
  })
end

return {
  version = 1,
  title = "Mixer Mono",
  root = ui.column {
    gap = 16,
    padding = 16,
    children = root_children
  }
}
