# Walking the tree from inside the picker: → descends, ← goes back up.
# Run from the repository root:  vhs demo/walk.tape

Output assets/hop-walk.gif

Set FontSize 18
Set Width 1200
Set Height 420
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms

Hide
Type "zsh demo/sandbox.zsh saved && env HOME=/private/tmp/demo HOPRC=/private/tmp/demo/.hoprc HOP_PLUGIN=$PWD/hop.plugin.zsh zsh -f"
Enter
Sleep 700ms
Type "cd && source $HOP_PLUGIN && PROMPT='%F{6}%~%f ❯ ' && clear"
Enter
Sleep 500ms
Show

Sleep 1s
Type "hop code/"
Sleep 700ms
Enter
Sleep 2s
Right
Sleep 1500ms
Left
Sleep 1500ms
Down
Sleep 1000ms
Right
Sleep 1500ms
Enter
Sleep 2s
