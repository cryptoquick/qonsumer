fs = require 'fs'
program = require 'commander'
qonsumer = require '../lib/qonsumer'

pkg = JSON.parse(fs.readFileSync('./package.json', 'utf8'))

program.version pkg.version
program.option '-c, --config', 'input configuration file'
program.option '-r, --results', 'directory to output results'
program.parse process.argv

qonsumer.init program
