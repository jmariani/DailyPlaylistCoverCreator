# Daily Playlist Cover Creator

A personal Ruby app to create daily playlist covers. The command-line application accepts source and destination folders plus a title as named parameters.

## Usage

```sh
bin/daily-playlist-cover-creator --source-folder /path/to/source/folder --destination-folder /path/to/destination/folder --title "Playlist Title"
```

Short switches are also supported:

```sh
bin/daily-playlist-cover-creator -s /path/to/source/folder -d /path/to/destination/folder -t "Playlist Title"
```

If any option is missing, the application prompts for it.

The application validates that the source folder exists and is a directory, creates the destination folder if it does not exist, and checks that the title is present.

It selects a random image by choosing a random item from the source folder. If the item is an image file, it copies the file to the destination folder. If the item is a folder, it repeats that selection inside the folder until an image file is found.

After an image is selected, the app copies it to the destination, opens the copied image with the default application, and asks you to approve it. Enter `y` or `yes` to continue. Any other answer removes that copied image and starts another random selection.

Supported image extensions are `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.bmp`, `.tif`, and `.tiff`.

The copied image keeps its original filename. If that filename already exists in the destination folder, the app appends a counter such as `cover-2.jpg`.

GPT title suggestion is planned for a later step.

The planned image enhancement prompt is:

```text
enhance. cinematic. keep aspect ratio. do not add text.
```

## Tests

```sh
ruby test/cli_test.rb
```
