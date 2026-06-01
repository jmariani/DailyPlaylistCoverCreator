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

The application validates that the provided folders exist and are directories, and that the title is present.

## Tests

```sh
ruby test/cli_test.rb
```
