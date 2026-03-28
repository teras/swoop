# Package
version       = "0.1.0"
author        = "teras"
description   = "Smart build artifact cleaner - detects project types and removes build cache"
license       = "MIT"
srcDir        = "src"
bin           = @["swoop"]

# Dependencies
requires "nim >= 2.0.0"
requires "parsetoml >= 0.7.0"
