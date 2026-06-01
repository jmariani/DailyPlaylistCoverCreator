# Daily Playlist Cover Creator

A personal Ruby app to create daily playlist covers. The command-line application accepts a source folder as a named parameter.

## Usage

```sh
bin/daily-playlist-cover-creator --source-folder /path/to/source/folder
```

The application validates that the provided source folder exists and is a directory.

## Tests

```sh
ruby test/cli_test.rb
```
