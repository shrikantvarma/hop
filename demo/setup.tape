# First run: no bookmarks yet. Star two folders from Settings, then search them.
# Run from the repository root:  vhs demo/setup.tape

Output assets/hop-setup.gif

Set FontSize 18
Set Width 1200
Set Height 520
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms

Hide
Type "zsh demo/sandbox.zsh fresh && env HOME=/private/tmp/demo HOPRC=/private/tmp/demo/.hoprc HOP_PLUGIN=$PWD/hop.plugin.zsh zsh -f"
Enter
Sleep 700ms
Type "cd && source $HOP_PLUGIN && PROMPT='%F{6}%~%f ❯ ' && clear"
Enter
Sleep 500ms
Show

Sleep 1s
Type "hop"
Sleep 500ms
Enter
Sleep 2s
Enter
Sleep 1800ms
Enter
Sleep 1500ms
Down
Sleep 1000ms
Enter
Sleep 1500ms
Escape
Sleep 1200ms
Escape
Sleep 2s
