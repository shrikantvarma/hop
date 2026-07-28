Output "assets/hop-demo.gif"

Set Shell zsh
Set Width 1000
Set Height 600
Set FontSize 24
Set Theme "Dracula"
Set TypingSpeed 1ms

# Load hop and point it at the safe demo tree.
Type "source hop.plugin.zsh"
Enter
Sleep 500ms
Type "export HOPRC=demo/hoprc"
Enter
Sleep 500ms

# Saved folders are starred and their nested files are already searchable.
Type "hop"
Enter
Sleep 2s

# Search a deep file and land in its parent folder.
Type "launch"
Sleep 2s
Enter
Sleep 1s
Type "basename $PWD"
Enter
Sleep 2s
