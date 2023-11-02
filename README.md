* Usage
```sh
# use an image
rock-paper-scissors images/garden.jpg
# or
rock-paper-scissors -i images/garden.jpg
# auto generate a board of solid colors
rock-paper-scissors
# auto generate a board of solid colors with a custom width and height
rock-paper-scissors 400x400
# or
rock-paper-scissors --width 400 --height 400
# use a custom size with an image:
rock-paper-scissors images/starry_night.jpg 500x600
# set a treshold
rock-paper-scissors --treshold 4
```
aliases:
-t -> --treshold
-w -> --width
-h -> --height
-i -> --image
