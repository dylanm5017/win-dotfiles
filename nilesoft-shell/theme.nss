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
		color = #333C43
		opacity = 100
	}

	item
	{
		opacity = 100
		radius = 0
		prefix = 1

		text
		{
			normal = #A7C080
			select = #A7C080
			normal-disabled = #859289
			select-disabled = #A7C080
		}

		back
		{
			select = #434F55
			select-disabled = #434F55
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
		color = #A7C080
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
		color = #333C43
	}

	symbol
	{
		normal = #A7C080
		select = #A7C080
		normal-disabled = #A7C0807a
		select-disabled = #A7C0807a
	}

	image
	{
		enabled = false
		color = [#A7C080, #A7C080, #A7C080]
	}
}
// win-dotfiles:theme:end
