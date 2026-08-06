// win-dotfiles Nilesoft Shell theme.
//
// Colors are NOT hand-edited: the block between the win-dotfiles:theme markers is regenerated
// by the `theme` command from the active palette (themes/<name>.psd1 -> YasbPalette), exactly
// like yasb's :root block and the VSCode workbench.colorCustomizations overlay.
//
// tools/Apply-NileSoftShell.ps1 copies this file into the installed Nilesoft Shell's
// imports\theme.nss (imported by its shell.nss), then reloads the shell so the context menu
// repaints. Only the color-bearing setters are palette-driven; layout/font stay static.

// win-dotfiles:theme:start
theme
{
	name = "win-dotfiles"

	view = view.small

	background
	{
		color = #1e1e2e
		opacity = 100
	}

	item
	{
		opacity = 100
		radius = 0
		prefix = 1

		text
		{
			normal = #cba6f7
			select = #cba6f7
			normal-disabled = #a6adc8
			select-disabled = #cba6f7
		}

		back
		{
			select = #45475a
			select-disabled = #45475a
		}
	}

	font
	{
		size = 16
		name = "JetBrainsMono NFP"
		weight = 1
		italic = 0
	}

	border
	{
		enabled = false
		size = 1
		color = #cba6f7
		opacity = 100
		radius = 0
	}

	shadow
	{
		enabled = true
		size = 5
		opacity = 5
		color = #11111b
	}

	separator
	{
		size = 1
		color = #1e1e2e
	}

	symbol
	{
		normal = #cba6f7
		select = #cba6f7
		normal-disabled = #cba6f77a
		select-disabled = #cba6f77a
	}

	image
	{
		enabled = false
		color = [#cba6f7, #cba6f7, #cba6f7]
	}
}
// win-dotfiles:theme:end
