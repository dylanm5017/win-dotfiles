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
		color = #F3EAD3
		opacity = 100
	}

	item
	{
		opacity = 100
		radius = 0
		prefix = 1

		text
		{
			normal = #8DA101
			select = #8DA101
			normal-disabled = #939F91
			select-disabled = #8DA101
		}

		back
		{
			select = #E5DFC5
			select-disabled = #E5DFC5
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
		color = #8DA101
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
		color = #F3EAD3
	}

	symbol
	{
		normal = #8DA101
		select = #8DA101
		normal-disabled = #8DA1017a
		select-disabled = #8DA1017a
	}

	image
	{
		enabled = false
		color = [#8DA101, #8DA101, #8DA101]
	}
}
// win-dotfiles:theme:end
