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
		color = #282828
		opacity = 100
	}

	item
	{
		opacity = 100
		radius = 0
		prefix = 1

		text
		{
			normal = #fe8019
			select = #fe8019
			normal-disabled = #a89984
			select-disabled = #fe8019
		}

		back
		{
			select = #504945
			select-disabled = #504945
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
		color = #fe8019
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
		color = #282828
	}

	symbol
	{
		normal = #fe8019
		select = #fe8019
		normal-disabled = #fe80197a
		select-disabled = #fe80197a
	}

	image
	{
		enabled = false
		color = [#fe8019, #fe8019, #fe8019]
	}
}
// win-dotfiles:theme:end
