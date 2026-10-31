local feature = require("proud.loader").load("pull_request_browser")
local debounce = require("proud.debounce")
local ui = require("proud.ui")
local util = require("proud.util")

local pulls = {}
for index = 1, 500 do
  table.insert(pulls, {
    number = 5000 + index,
    title = "Improve retry path " .. index .. " with deterministic backoff",
    author = { login = "author-" .. (index % 17) },
    age = (index % 12) .. "h",
    additions = index % 400,
    deletions = index % 90,
    threads = index % 8,
    review_decision = index % 2 == 0 and "REVIEW_REQUIRED" or "CHANGES_REQUESTED",
    is_draft = false,
    labels = { "runner", "performance" },
    head_ref = "feat/retry-" .. index,
    base_ref = "main",
  })
end
local description = {}
for index = 1, 100 do
  table.insert(description, ("Description line %d for deterministic preview rendering."):format(index))
end
pulls[1].body = table.concat(description, "\n")
local loaded_pulls = vim.list_slice(pulls, 1, 100)
local state = feature.create(loaded_pulls, { query = "retry is:open" })

local opening_pulls = {}
for index = 1, 25 do
  opening_pulls[index] = vim.deepcopy(pulls[index])
  opening_pulls[index].body = nil
end
opening_pulls[1].body = table.concat(description, "\n")

local opening_workload = {
  options = {
    name = "pull_request_browser.open_25_visible_prs_from_500",
    iterations = 30,
    warmup = 5,
  },
  sla = {
    p95_ms = 2,
    max_memory_kb = 256,
  },
  run = function()
    local opening_state = feature.create({}, { query = "retry is:open" })
    feature.apply_page(opening_state, {
      pulls = opening_pulls,
      total_count = 500,
      has_next_page = true,
      next_cursor = "25",
    }, { replace = true })
    local list = feature.render_list(opening_state, { width = 72 })
    local preview = feature.render_preview(opening_state, { width = 72 })
    local selector = ui.selector_layout(feature.sources(), 3, 120)
    return #list.lines + #preview.lines + #selector.text + #feature.count_label(opening_state)
  end,
}

local prefetch_workload = {
  options = {
    name = "pull_request_browser.prefetch_two_pages_from_500",
    iterations = 30,
    warmup = 5,
  },
  sla = {
    p95_ms = 2,
    max_memory_kb = 256,
  },
  run = function()
    local prefetch_state = feature.create({}, { query = "retry is:open" })
    for page = 0, 2 do
      feature.apply_page(prefetch_state, {
        pulls = vim.list_slice(pulls, page * 25 + 1, page * 25 + 25),
        total_count = 500,
        has_next_page = page < 2,
        next_cursor = tostring((page + 1) * 25),
      }, { replace = page == 0 })
    end
    feature.move(prefetch_state, 1)
    return #prefetch_state.pulls
  end,
}

local render_workload = {
  options = {
    name = "pull_request_browser.render_100_loaded_prs_100_line_description",
    iterations = 30,
    warmup = 5,
  },
  sla = {
    p95_ms = 3,
    max_memory_kb = 512,
  },
  run = function()
    local list = feature.render_list(state, { width = 72 })
    local preview = feature.render_preview(state, { width = 72 })
    return #list.lines + #preview.lines + #feature.count_label(state)
  end,
}

local preview_focus_state = feature.create(loaded_pulls, { query = "retry is:open" })
local preview_focus_workload = {
  options = {
    name = "pull_request_browser.focus_explore_preview_100_lines",
    iterations = 40,
    warmup = 5,
  },
  sla = {
    p95_ms = 1,
    max_memory_kb = 128,
  },
  run = function()
    local preview = feature.render_preview(preview_focus_state, { width = 72 })
    local row = math.min(3, #preview.lines)
    return row + (#preview.lines > row and 1 or 0)
  end,
}

local debounced = debounce.new(250, function() end)
local debounce_workload = {
  options = {
    name = "pull_request_browser.debounce_200_filter_edits",
    iterations = 25,
    warmup = 3,
  },
  sla = {
    p95_ms = 2,
    max_memory_kb = 256,
  },
  run = function()
    for index = 1, 200 do
      debounced:schedule(index)
    end
    debounced:cancel()
    return 0
  end,
}

local description_debounced = debounce.new(80, function() end)
local description_debounce_workload = {
  options = {
    name = "pull_request_browser.debounce_200_description_selections",
    iterations = 25,
    warmup = 3,
  },
  sla = {
    p95_ms = 2,
    max_memory_kb = 256,
  },
  run = function()
    for index = 1, 200 do
      description_debounced:schedule(8000 + index)
    end
    description_debounced:cancel()
    return 0
  end,
}

local source_queries = {}
for _, source in ipairs(feature.sources()) do
  table.insert(source_queries, source.query)
end
local source_debounced = debounce.new(250, function() end)
local source_debounce_workload = {
  options = {
    name = "pull_request_browser.debounce_200_source_changes",
    iterations = 25,
    warmup = 3,
  },
  sla = {
    p95_ms = 2,
    max_memory_kb = 256,
  },
  run = function()
    for index = 1, 200 do
      source_debounced:schedule(source_queries[(index % #source_queries) + 1], index)
    end
    source_debounced:cancel()
    return 0
  end,
}

local count_state = feature.create(pulls, { query = "retry is:open" })
local count_edit = 0
local filter_count_workload = {
  options = {
    name = "pull_request_browser.filter_and_count_500_prs",
    iterations = 40,
    warmup = 5,
  },
  sla = {
    p95_ms = 3,
    max_memory_kb = 512,
  },
  run = function()
    count_edit = count_edit + 1
    feature.set_query(count_state, count_edit % 2 == 0 and "label:missing" or "retry is:open")
    return feature.count_label(count_state)
  end,
}

local relative_now = assert(util.parse_iso8601("2026-10-15T12:00:00Z"))
local timestamps = {}
for index = 1, 2000 do
  table.insert(timestamps, ("2026-10-15T%02d:%02d:%02dZ"):format(
    index % 24,
    index % 60,
    index % 60
  ))
end
local relative_time_workload = {
  options = {
    name = "pull_request_browser.relative_time_2000_timestamps",
    iterations = 30,
    warmup = 5,
  },
  sla = {
    p95_ms = 3,
    max_memory_kb = 384,
  },
  run = function()
    local checksum = 0
    for _, timestamp in ipairs(timestamps) do
      checksum = checksum + #util.relative_time(timestamp, { now = relative_now })
    end
    return checksum
  end,
}

return {
  workloads = {
    opening_workload,
    prefetch_workload,
    render_workload,
    preview_focus_workload,
    debounce_workload,
    description_debounce_workload,
    source_debounce_workload,
    filter_count_workload,
    relative_time_workload,
  },
}
