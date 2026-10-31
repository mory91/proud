return function(test)
  local feature = require("proud.loader").load("github_credentials")
  local bit = require("bit")
  local uv = vim.uv or vim.loop

  test.eq("github_credentials", feature.name)
  test.eq("github_pat_trimmed", feature.normalize_token("  Bearer github_pat_trimmed\n"))
  test.eq("github_pat_token_prefix", feature.normalize_token("token github_pat_token_prefix"))

  local token_path = vim.fn.tempname()
  test.truthy(feature.write_token(token_path, "github_pat_saved"))
  test.eq("github_pat_saved", feature.read_token(token_path))
  local stat = uv.fs_stat(token_path)
  test.truthy(stat, "credential file exists")
  test.eq(384, bit.band(stat.mode, 511), "credential file is owner-readable only")

  local previous_env = vim.env.PROUD_GITHUB_TOKEN
  vim.env.PROUD_GITHUB_TOKEN = "github_pat_environment"
  local done, source, resolved = false
  feature.resolve_candidate({
    token_path = token_path,
    credential = false,
    cwd = vim.fn.getcwd(),
  }, function(value, value_source)
    done, resolved, source = true, value, value_source
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.eq("github_pat_environment", resolved)
  test.eq("environment", source, "environment overrides stale saved credentials")
  vim.env.PROUD_GITHUB_TOKEN = previous_env

  done = false
  feature.resolve_candidate({
    token_path = token_path,
    credential = false,
    cwd = vim.fn.getcwd(),
  }, function(value, value_source)
    done, resolved, source = true, value, value_source
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.eq("github_pat_saved", resolved)
  test.eq("stored", source)

  local state = feature.create({
    token_path = token_path,
    error = "HTTP 401: Bad credentials",
  })
  local view = feature.render(state)
  local text = table.concat(view.lines, "\n")
  test.contains(text, "GitHub token required")
  test.contains(text, "HTTP 401: Bad credentials")
  test.contains(text, "repository read access")
  test.contains(text, "type the token in the page below")
  test.contains(text, "reused on later launches")
  test.truthy(not text:find("github_pat_saved", 1, true), "rendered modal never exposes stored tokens")
  test.highlighted(view, "Error", "ProudDangerText", "validation errors are destructive")
  test.highlighted(view, "repository read access", "ProudSuccessText", "required access is highlighted")

  local prompt_buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buffer].buftype = "nofile"
  vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, { "github_pat_mask_me" })
  feature.mask_prompt(prompt_buffer)
  local namespace = vim.api.nvim_get_namespaces().proud_credentials_prompt_sign
  test.eq(1, #vim.api.nvim_buf_get_extmarks(prompt_buffer, namespace, 0, -1, {}), "prompt masking installs one sign")
  feature.mask_prompt(prompt_buffer)
  test.eq(1, #vim.api.nvim_buf_get_extmarks(prompt_buffer, namespace, 0, -1, {}), "prompt masking is idempotent")
  test.truthy(vim.b[prompt_buffer].proud_prompt_masked, "prompt syntax masking is configured once per buffer")
  vim.api.nvim_buf_delete(prompt_buffer, { force = true })

  local saved = false
  done = false
  feature.submit(state, "  Bearer github_pat_rejected  ", {
    validate = function(token, callback)
      test.eq("github_pat_rejected", token)
      callback(false, { message = "HTTP 401: Token rejected" })
    end,
    on_success = function()
      saved = true
    end,
  }, function(ok)
    done = true
    test.truthy(not ok)
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.truthy(not saved)
  test.eq("HTTP 401: Token rejected", state.error)
  test.truthy(not state.error:find("github_pat_rejected", 1, true))

  done = false
  feature.submit(state, "github_pat_accepted", {
    validate = function(token, callback)
      callback(token == "github_pat_accepted", token == "github_pat_accepted" and {} or { message = "rejected" })
    end,
    on_success = function(token)
      saved = token
    end,
  }, function(ok)
    done = true
    test.truthy(ok)
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  test.eq("github_pat_accepted", saved)
  test.eq("github_pat_accepted", feature.read_token(token_path), "successful entry replaces rejected saved credential")
end
