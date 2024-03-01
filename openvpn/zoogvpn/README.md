# How to update files

* Download configuration archives from ZoogVPN web site
* Extract in directory
* Use this shell command to rename the files

$ for f in *.ovpn; do ./rename_file.sh "$f"; done

