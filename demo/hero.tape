# Half-remember a folder name, fuzzy-find it, land, start working.
# Run from the repository root:  vhs demo/hero.tape

Output assets/hop-demo.gif

Set FontSize 18
Set Width 1200
Set Height 480
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
Type "hop obs"
Sleep 800ms
Enter
Sleep 2s
Down
Sleep 900ms
Down
Sleep 900ms
Down
Sleep 1200ms
Enter
Sleep 1500ms
Type "claude"
Sleep 2500ms
