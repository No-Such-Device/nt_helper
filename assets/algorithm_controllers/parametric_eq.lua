local function parameter_text(parameter)
  if parameter == nil then return "Unavailable" end
  local enum = parameter.enum_values[parameter.value + 1]
  if enum ~= nil and enum ~= "" then return enum end
  if parameter.display_value ~= "" then return parameter.display_value end
  return tostring(parameter.value)
end

local function normalized_value(parameter)
  if parameter == nil or parameter.maximum == parameter.minimum then return 0 end
  return math.max(
    0,
    math.min(
      1,
      (parameter.value - parameter.minimum) /
        (parameter.maximum - parameter.minimum)
    )
  )
end

local function engineering_value(parameter)
  if parameter == nil then return 0 end
  return parameter.value * (10 ^ parameter.power_of_ten)
end

local function band_parameter(channel, band, name)
  return nt.channel_parameter(channel, band .. ":" .. name)
end

local function discover_bands(channel)
  local discovered = {}
  local prefix = nt.channel_prefix(channel)
  if prefix == nil then return {} end
  for _, parameter in ipairs(algorithm.parameters) do
    local first_separator = string.find(parameter.name, ":", 1, true)
    if first_separator ~= nil then
      local found_channel = string.sub(parameter.name, 1, first_separator - 1)
      local remainder = string.sub(parameter.name, first_separator + 1)
      local second_separator = string.find(remainder, ":", 1, true)
      if found_channel == prefix and second_separator ~= nil and
          string.sub(remainder, second_separator + 1) == "Enable" then
        local found_band =
          tonumber(string.sub(remainder, 1, second_separator - 1))
        if found_band ~= nil then discovered[found_band] = true end
      end
    end
  end

  local bands = {}
  for band, _ in pairs(discovered) do table.insert(bands, band) end
  table.sort(bands)
  return bands
end

local function response_for_band(band, position)
  if band.enabled.value == 0 then return 0 end

  local filter_type = band.filter_type.value
  local centre = normalized_value(band.frequency)
  local q_amount = normalized_value(band.q)
  local gain = engineering_value(band.gain)
  local width = 0.18 - q_amount * 0.14
  local distance = position - centre
  local gaussian = math.exp(-0.5 * (distance / width) ^ 2)

  if filter_type == 0 then
    return -9 / (1 + math.exp(-(position - centre) / width))
  elseif filter_type == 1 then
    return -9 / (1 + math.exp((position - centre) / width))
  elseif filter_type == 2 then
    return -16 / (1 + math.exp(-(position - centre) / width)) +
      q_amount * 4 * gaussian
  elseif filter_type == 3 then
    return -16 / (1 + math.exp((position - centre) / width)) +
      q_amount * 4 * gaussian
  elseif filter_type == 4 then
    return gain / (1 + math.exp((position - centre) / width))
  elseif filter_type == 5 then
    return gain / (1 + math.exp(-(position - centre) / width))
  end
  return gain * gaussian
end

local function total_response(bands, position)
  local response = 0
  for _, band in ipairs(bands) do
    response = response + response_for_band(band, position)
  end
  return response
end

local function response_y(response)
  return math.max(0.08, math.min(0.92, 0.5 - response / 36))
end

local function response_shapes(bands)
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
      y1 = 0.5,
      x2 = 0.96,
      y2 = 0.5,
      stroke = "outline"
    }
  }

  for division = 1, 3 do
    local x = 0.04 + (division / 4) * 0.92
    table.insert(shapes, ui.line {
      x1 = x,
      y1 = 0.1,
      x2 = x,
      y2 = 0.9,
      stroke = "outline",
      stroke_width = 1
    })
  end

  local previous = nil
  for sample = 0, 56 do
    local position = sample / 56
    local point = {
      x = 0.04 + position * 0.92,
      y = response_y(total_response(bands, position))
    }
    if previous ~= nil then
      table.insert(shapes, ui.line {
        x1 = previous.x,
        y1 = previous.y,
        x2 = point.x,
        y2 = point.y,
        stroke = "primary",
        stroke_width = 3
      })
    end
    previous = point
  end

  local colours = { "primary", "secondary", "tertiary" }
  for index, band in ipairs(bands) do
    if band.enabled.value ~= 0 then
      local position = normalized_value(band.frequency)
      table.insert(shapes, ui.circle {
        x = 0.04 + position * 0.92,
        y = response_y(total_response(bands, position)),
        radius = 0.025,
        fill = colours[((index - 1) % #colours) + 1],
        stroke = "surface"
      })
    end
  end

  return shapes
end

local function response_description(channel, bands)
  local descriptions = {}
  for _, band in ipairs(bands) do
    if band.enabled.value ~= 0 then
      local text = "band " .. band.number .. " " ..
        parameter_text(band.filter_type) .. " at " ..
        parameter_text(band.frequency)
      if band.filter_type.value >= 4 then
        text = text .. ", gain " .. parameter_text(band.gain)
      end
      if band.filter_type.value == 2 or band.filter_type.value == 3 or
          band.filter_type.value == 6 then
        text = text .. ", Q " .. parameter_text(band.q)
      end
      table.insert(descriptions, text)
    end
  end

  if #descriptions == 0 then
    return "Illustrative flat EQ preview for channel " .. channel ..
      " because every band is disabled. This is not a measured response."
  end
  return "Illustrative combined EQ preview for channel " .. channel .. ": " ..
    table.concat(descriptions, "; ") ..
    ". This is a stylized curve, not a measured response."
end

local channel_sections = {}

for _, channel in ipairs(nt.channels()) do
  local width = nt.channel_parameter(channel, "Width")
  local band_numbers = discover_bands(channel)
  local bands = {}

  for _, band_number in ipairs(band_numbers) do
    local enabled = band_parameter(channel, band_number, "Enable")
    local filter_type = band_parameter(channel, band_number, "Type")
    local frequency = band_parameter(channel, band_number, "Frequency")
    local q = band_parameter(channel, band_number, "Q")
    local gain = band_parameter(channel, band_number, "Gain")
    if enabled ~= nil and filter_type ~= nil and frequency ~= nil and
        q ~= nil and gain ~= nil then
      table.insert(bands, {
        number = band_number,
        enabled = enabled,
        filter_type = filter_type,
        frequency = frequency,
        q = q,
        gain = gain
      })
    end
  end

  if width ~= nil and #bands > 0 then
    local children = {
      ui.canvas {
        semantics_label = response_description(channel, bands),
        aspect_ratio = 5.2,
        shapes = response_shapes(bands)
      },
      ui.slider {
        label = "Bus width",
        parameter = width.number
      }
    }

    for _, band in ipairs(bands) do
      local band_children = {
        ui.toggle {
          label = "Enabled",
          parameter = band.enabled.number
        },
        ui.choice {
          label = "Type",
          parameter = band.filter_type.number
        },
        ui.slider {
          label = "Frequency",
          parameter = band.frequency.number
        }
      }
      if band.filter_type.value == 2 or band.filter_type.value == 3 or
          band.filter_type.value == 6 then
        table.insert(band_children, ui.slider {
          label = "Q",
          parameter = band.q.number
        })
      end
      if band.filter_type.value >= 4 then
        table.insert(band_children, ui.slider {
          label = "Gain",
          parameter = band.gain.number
        })
      end

      local subtitle = parameter_text(band.filter_type) .. " · " ..
        parameter_text(band.frequency)
      if band.filter_type.value >= 4 then
        subtitle = subtitle .. " · " .. parameter_text(band.gain)
      end
      table.insert(children, ui.section {
        title = "Band " .. band.number,
        subtitle = subtitle,
        children = band_children
      })
    end

    table.insert(channel_sections, ui.section {
      title = "Channel " .. channel,
      subtitle = #bands .. " bands · width " .. parameter_text(width),
      children = children
    })
  end
end

if #channel_sections == 0 then
  table.insert(channel_sections, ui.text {
    text = "No parametric EQ channels were found in this slot.",
    style = "body"
  })
end

return {
  version = 1,
  title = "EQ Parametric",
  root = ui.column {
    gap = 16,
    padding = 16,
    children = channel_sections
  }
}
