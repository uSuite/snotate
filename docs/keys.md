# sNotate keys

Generated from the built-in keymap by `make cheatsheet`; do not edit by hand. Lines in `~/.config/snotate/keymap` apply on top of these, and `<keys> nop` removes one. Digits choose a style preset, so there are no count prefixes. Hold `space` and drag to pan.

## Steps

| Keys | Command |
| --- | --- |
| `j` | next |
| `k` | previous |
| `gg` | first |
| `G` | last |
| `J` | move-step-later |
| `K` | move-step-earlier |
| `dd` | remove-step |
| `:` | command-line |

### Views

| Keys | Command |
| --- | --- |
| `<cmd-1>` | view-step |
| `<cmd-2>` | view-storyboard |
| `i` | edit-caption |

### Cases

| Keys | Command |
| --- | --- |
| `]` | case-next |
| `[` | case-previous |

## Tools

| Keys | Command |
| --- | --- |
| `v` | tool select |
| `<esc>` | tool select |
| `a` | tool arrow |
| `r` | tool rectangle |
| `e` | tool ellipse |
| `n` | tool counter |
| `N` | restart-counter |
| `t` | tool text |
| `h` | tool highlight |
| `b` | tool blur |
| `c` | tool crop |
| `C` | crop-previous |

### The step

| Keys | Command |
| --- | --- |
| `x` | exclude |
| `>` | stamp-following |
| `<` | stamp-previous |

## The selection

| Keys | Command |
| --- | --- |
| `<cmd-a>` | select-all |
| `<backspace>` | delete |
| `<delete>` | delete |
| `<cmd-d>` | duplicate |
| `f` | fill |
| `<enter>` | edit |
| `<cmd-[>` | send-backward |
| `<cmd-]>` | bring-forward |
| `<left>` | nudge-left |
| `<right>` | nudge-right |
| `<up>` | nudge-up |
| `<down>` | nudge-down |
| `<shift-left>` | nudge-left-10 |
| `<shift-right>` | nudge-right-10 |
| `<shift-up>` | nudge-up-10 |
| `<shift-down>` | nudge-down-10 |

## View

| Keys | Command |
| --- | --- |
| `=` | zoom-fit |
| `0` | zoom-actual |
| `+` | zoom-in |
| `-` | zoom-out |
| `z` | zoom-area |

### Presets

| Keys | Command |
| --- | --- |
| `1` | preset 1 |
| `2` | preset 2 |
| `3` | preset 3 |
| `4` | preset 4 |
| `5` | preset 5 |
| `6` | preset 6 |
| `7` | preset 7 |
| `8` | preset 8 |
| `9` | preset 9 |

## Export

| Keys | Command |
| --- | --- |
| `<cmd-e>` | export |
| `<cmd-E>` | export-step |
| `<cmd-C>` | copy-step |

### History

| Keys | Command |
| --- | --- |
| `<cmd-z>` | undo |
| `<cmd-Z>` | redo |

## Help

| Keys | Command |
| --- | --- |
| `?` | help |

## Command line only

Typed after `:`; any command above works there too, as the keymap writes it.

| Command | Does |
| --- | --- |
| `:<n>` | go to step n; `go-to <n>` is the same |
| `:excluded` | list the excluded steps |
| `:deselect` | clear the selection |
| `:end-text-edit` | finish typing into a text annotation |
| `:stamp-next` | stamp the selected blur and highlight regions, or the crop while cropping, onto the next step |
| `:stamp-all` | the same onto every other step |
| `:rename-plan` | show the renames story order asks for, applied only on confirm |
| `:set <key> <value>` | change one line of ~/.config/snotate/config |
| `:export-config [path]` | zip config, keymap and styles, to the Desktop by default |
