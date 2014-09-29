fs = require 'fs'
program = require 'commander'
qonsume = require '../lib/qonsume'

pkg = JSON.parse(fs.readFileSync('./package.json', 'utf8'))

program.version pkg.version
program.option '-c, --config', 'input configuration file'
program.option '-r, --results', 'directory to output results'
program.parse process.argv

qonsume.init program
