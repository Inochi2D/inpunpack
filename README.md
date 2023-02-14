# INPUnpack
A small utiltiy that allows unpacking and repacking a packed INP file for study and data recovery purposes.


# Usage Instructions
```
inpunpack: Pack and unpack Inochi2D INP and INX files (1.1)

USAGE
  $ inpunpack [-h] [--version] pack|unpack

FLAGS
  -h, --help                prints help
      --version             prints version

SUBCOMMANDS
  pack                      Pack INP file
  unpack                    Unpack INP file
```

## Unpacking
```
inpunpack unpack: Unpack INP file

USAGE
  $ inpunpack unpack [-h] [-r] files 

FLAGS
  -h, --help                prints help
  -r, --raw                 Unpack without validating JSON

ARGUMENTS
  files                     Files to unpack
```

## Packing
```
inpunpack pack: Pack INP file

USAGE
  $ inpunpack pack [-h] paths 

FLAGS
  -h, --help                prints help

ARGUMENTS
  paths                     Paths/directories to pack
```