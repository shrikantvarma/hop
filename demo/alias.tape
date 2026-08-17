# An exact alias skips the picker entirely.
# Run from the repository root:  vhs demo/alias.tape

Output assets/hop-alias.gif

Set FontSize 18
Set Width 1200
Set Height 260
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 70ms

Hide
Type "zsh demo/sandbox.zsh saved && env HOME=/private/tmp/demo HOPRC=/private/tmp/demo/.hoprc HOP_PLUGIN=$PWD/hop.plugin.zsh zsh -f"
Enter
Sleep 700ms
Type "cd && source $HOP_PLUGIN && PROMPT='%F{6}%~%f ❯ ' && clear"
Enter
Sleep 500ms
Show

Sleep 1s
Type "hop code"
Sleep 600ms
Enter
Sleep 1800ms
Type "hop obsidian"
Sleep 600ms
Enter
Sleep 2s
