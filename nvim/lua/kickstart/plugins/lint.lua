return {

	{ -- Linting
		"mfussenegger/nvim-lint",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			local lint = require("lint")
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

			-- Create autocommand which carries out the actual linting
			-- on the specified events.
			local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
			vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
				group = lint_augroup,
				callback = function()
					if not vim.opt_local.modifiable:get() then
						return
					end

					if vim.bo.filetype == "python" then
						-- Resolve mypy executable from active virtualenv or cwd .venv
						local mypy_cmd = "mypy"
						local candidates = {
							(vim.env.VIRTUAL_ENV or "") .. "/bin/mypy",
							vim.fn.getcwd() .. "/.venv/bin/mypy",
						}
						for _, candidate in ipairs(candidates) do
							if candidate ~= "/bin/mypy" and vim.fn.filereadable(candidate) == 1 then
								mypy_cmd = candidate
								break
							end
						end
						lint.linters.mypy.cmd = mypy_cmd

						-- Append --config-file if a project-specific mypy config exists
						local mypy = require("lint.linters.mypy")
						local base_args = {
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
							vim.list_extend(base_args, { "--config-file", vim.fn.fnamemodify(config, ":p") })
						end
						mypy.args = base_args
					end

					lint.try_lint()
				end,
			})
		end,
	},
}
