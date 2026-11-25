# RU dictionary repair (archived)

Not supported and not documented. Kept for reference only.

`repair-ru-dictionary.sh` reloaded Oracle catalog scripts to add the dictionary
objects that a 23.26.x image swap does not install. The supported ways to move to
a new release update are an image swap plus `fix-jvm`, or `rebuild`
(export and import into a new database).

The files expect to run from `scripts/`. Copy them back there to use them.
