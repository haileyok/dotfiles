return {

	{ -- Linting
		"mfussenegger/nvim-lint",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			local lint = require("lint")
			local dmypy_configured = false
			local last_branch = nil
			lint.linters_by_ft = {
				typescript = { "eslint" },
				typescriptreact = { "eslint" },
				javascript = { "eslint" },
				javascriptreact = { "eslint" },
				python = { "mypy" },
				html = { "htmlhint" },
				dockerfile = { "hadolint" },
				rust = { "clippy" },
			}

			-- However, note that this will enable a set of default linters,
			-- which will cause errors unless these tools are available:
			-- {
			--   clojure = { "clj-kondo" },
			--   dockerfile = { "hadolint" },
			--   inko = { "inko" },
			--   janet = { "janet" },
			--   json = { "jsonlint" },
			--   markdown = { "vale" },
			--   rst = { "vale" },
			--   ruby = { "ruby" },
			--   terraform = { "tflint" },
			--   text = { "vale" }
			-- }
			--
			-- You can disable the default linters by setting their filetypes to nil:
			-- lint.linters_by_ft['clojure'] = nil
			-- lint.linters_by_ft['dockerfile'] = nil
			-- lint.linters_by_ft['inko'] = nil
			-- lint.linters_by_ft['janet'] = nil
			-- lint.linters_by_ft['json'] = nil
			-- lint.linters_by_ft['markdown'] = nil
			-- lint.linters_by_ft['rst'] = nil
			-- lint.linters_by_ft['ruby'] = nil
			-- lint.linters_by_ft['terraform'] = nil
			-- lint.linters_by_ft['text'] = nil

			-- Restart dmypy when git branch changes to avoid stale cache
			vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave" }, {
				group = vim.api.nvim_create_augroup("dmypy-branch-watch", { clear = true }),
				callback = function()
					local branch = vim.fn.system("git rev-parse --abbrev-ref HEAD 2>/dev/null"):gsub("\n", "")
					if last_branch and branch ~= last_branch then
						vim.fn.system("dmypy stop 2>/dev/null")
						dmypy_configured = false
					end
					last_branch = branch
				end,
			})

			-- Create autocommand which carries out the actual linting
			-- on the specified events.
			local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
			vim.api.nvim_create_autocmd({ "BufWritePost" }, {
				group = lint_augroup,
				callback = function()
					if not vim.opt_local.modifiable:get() then
						return
					end

					if vim.bo.filetype == "python" and not dmypy_configured then
						dmypy_configured = true

						-- Find dmypy binary (co-located with mypy)
						local dmypy_cmd = "dmypy"
						local candidates = {
							(vim.env.VIRTUAL_ENV or "") .. "/bin/dmypy",
							vim.fn.getcwd() .. "/.venv/bin/dmypy",
						}
						for _, candidate in ipairs(candidates) do
							if candidate ~= "/bin/dmypy" and vim.fn.filereadable(candidate) == 1 then
								dmypy_cmd = candidate
								break
							end
						end

						local dmypy_args = {
							"run",
							"--",
							"--show-column-numbers",
							"--show-error-end",
							"--hide-error-context",
							"--no-color-output",
							"--no-error-summary",
							"--no-pretty",
						}
						local config = vim.fn.findfile(
							"discord_clyde/configs/mypy_discord_safety_dispatch_lax.ini",
							vim.fn.getcwd() .. ";"
						)
						if config ~= "" then
							vim.list_extend(dmypy_args, { "--config-file", vim.fn.fnamemodify(config, ":p") })
						end

						lint.linters.mypy.cmd = dmypy_cmd
						require("lint.linters.mypy").args = dmypy_args
					end

					lint.try_lint()
				end,
			})
		end,
	},
}
