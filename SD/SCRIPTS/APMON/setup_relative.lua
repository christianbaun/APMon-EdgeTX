-- SPDX-License-Identifier: Apache-2.0
-- APMon: locate the exact, explicitly verified source used by the armed summary.
-- Project version: 1.2.0
return function(monitor, config, name)
  local candidate
  for _, key in ipairs({'altitude', 'gpsaltitude'}) do
    local entry, def = monitor.sources[key], config.sensors[key]
    if entry and def then
      for _, alias in ipairs(def.names) do
        if alias == name then
          if entry.name == name then
            if entry.state == 'valid' then return 'valid', name end
            candidate = entry
          elseif not candidate then
            candidate = entry
          end
          break
        end
      end
    end
  end
  if not candidate then return 'unmapped' end
  local state = candidate.state
  if state == 'noapi' or state == 'missing' then return state end
  if candidate.name ~= name then return 'unselected', state == 'valid' and candidate.name or nil end
  return state, name
end
