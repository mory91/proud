local feature = require("proud.loader").load("pull_request_browser")
local session = require("proud.session")

local page_requests = {}
local description_requests = {}
local pulls = {}
for index = 1, 40 do
  table.insert(pulls, {
    number = 8000 + index,
    title = "Lazy pull request " .. index,
    author = { login = "lazy-author-" .. index },
    age = index .. "m",
    additions = index,
    deletions = 1,
    threads = index % 3,
    review_decision = "REVIEW_REQUIRED",
  })
end

local state = feature.create({}, { query = "is:open" })
local buffer = feature.open(state, {
  query_debounce_ms = 50,
  description_debounce_ms = 50,
  on_page = function(page, callback)
    table.insert(page_requests, page)
    local offset = page.after == "" and 0 or tonumber(page.after) or 0
    local items = {}
    for index = offset + 1, math.min(offset + page.limit, #pulls) do
      table.insert(items, vim.deepcopy(pulls[index]))
    end
    callback(true, {
      pulls = items,
      total_count = #pulls,
      has_next_page = offset + #items < #pulls,
      next_cursor = tostring(offset + #items),
    })
  end,
  on_description = function(number, callback)
    table.insert(description_requests, number)
    callback(true, "Lazy first message for pull request #" .. number)
  end,
})
session.current = { feature = "pull_request_browser", state = state, buffer = buffer }

assert(vim.wait(1000, function()
  return state.page_loaded and state.filtered[1] and state.filtered[1].description_loaded
end, 10), "initial page and preselected description did not load")

local page_size = feature.page_size_for_height(vim.api.nvim_win_get_height(state.window))
assert(page_requests[1].limit == page_size, "initial page limit does not match the visible list")
assert(#state.pulls == page_size, "initial load fetched more than one visible page")
assert(#description_requests == 1 and description_requests[1] == 8001, "only the preselected description was fetched")
assert(
  table.concat(vim.api.nvim_buf_get_lines(state.preview_buffer, 0, -1, false), "\n")
    :find("Lazy first message", 1, true),
  "preselected description did not render"
)
vim.api.nvim_echo({
  { ("LAZY_PAGINATION_INITIAL_OK=true page=%d total=%d descriptions=%d"):format(page_size, #pulls, #description_requests) },
}, false, {})

local selector = state.surface.selector
assert(selector and selector.get_selected() == 3, "All open is not the default source")
local selector_text = table.concat(vim.api.nvim_buf_get_lines(selector.buffer, 0, -1, false), "\n")
for _, label in ipairs({ "Review requested", "Mine", "All open", "Recently viewed", "Branches" }) do
  assert(selector_text:find(label, 1, true), "source selector is missing " .. label)
end

function ProudLazyPaginationAssertSelection()
  local selected = state.filtered[state.cursor]
  assert(selected, "no pull request is selected")
  assert(vim.wait(500, function()
    return selected.description_loaded
  end, 10), "selected description did not settle")
  local found = false
  for _, number in ipairs(description_requests) do
    found = found or number == selected.number
  end
  assert(found, "selected pull request description was not fetched on demand")
  local text = table.concat(vim.api.nvim_buf_get_lines(state.preview_buffer, 0, -1, false), "\n")
  assert(text:find("Lazy first message", 1, true), "selected description is not visible")
  vim.api.nvim_echo({
    { ("LAZY_DESCRIPTION_CURSOR_OK=true selected=%d descriptions=%d"):format(selected.number, #description_requests) },
  }, false, {})
end

function ProudLazyPaginationAssertNextPage()
  assert(vim.wait(1000, function()
    return #state.pulls >= math.min(#pulls, page_size * 3) and #page_requests >= 3
  end, 10), "two cursor pages did not prefetch after cursor movement")
  assert(page_requests[2].after == tostring(page_size), "next page did not resume from the API cursor")
  assert(page_requests[3].after == tostring(page_size * 2), "second prefetch page stayed sequential")
  assert(#state.pulls <= page_size * 3, "pagination loaded more than two additional pages")
  vim.api.nvim_echo({
    { ("LAZY_PAGE_LOAD_OK=true loaded=%d total=%d pages=%d descriptions=%d"):format(#state.pulls, #pulls, #page_requests, #description_requests) },
  }, false, {})
end

function ProudLazyPaginationAssertBudget()
  assert(#page_requests == 3, "cursor movement requested more than two prefetch pages")
  local selected = state.filtered[state.cursor]
  assert(vim.wait(500, function()
    return selected and selected.description_loaded
  end, 10), "settled cursor description did not load")
  assert(#description_requests <= 3, "held cursor movement fetched intermediate descriptions")
  vim.api.nvim_echo({
    { ("LAZY_FETCH_BUDGET_OK=true pages=%d descriptions=%d available=%d"):format(#page_requests, #description_requests, #pulls) },
  }, false, {})
end

function ProudLazyPaginationAssertRapidSources()
  assert(vim.wait(500, function()
    return selector.get_selected() == 3 and #page_requests >= 4
  end, 10), "rapid source movement did not settle on All open")
  assert(selector.get_selected() == 3, "rapid source movement changed the settled source")
  assert(#page_requests == 4, "rapid source movement fetched intermediate source lists")
  assert(page_requests[4].query == "is:open", "rapid source movement fetched the wrong settled query")
  vim.api.nvim_echo({ { "SOURCE_TAB_RAPID_OK=true selected=3 pages=4" } }, false, {})
end

function ProudLazyPaginationAssertNextSource()
  assert(vim.wait(500, function()
    return selector.get_selected() == 4 and #page_requests >= 5
  end, 10), "next source did not select and reload Recently viewed")
  assert(page_requests[5].query == "is:open interacted-by:@me sort:updated-desc", "next source loaded the wrong query")
  vim.api.nvim_echo({ { "SOURCE_TAB_NEXT_OK=true selected=4 pages=5" } }, false, {})
end

function ProudLazyPaginationAssertPreviousSource()
  assert(vim.wait(500, function()
    return selector.get_selected() == 3 and #page_requests >= 6
  end, 10), "previous source did not return to All open")
  assert(page_requests[6].query == "is:open", "previous source loaded the wrong query")
  vim.api.nvim_echo({ { "SOURCE_TAB_PREVIOUS_OK=true selected=3 pages=6" } }, false, {})
end
