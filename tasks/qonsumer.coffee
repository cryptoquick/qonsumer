qonsumer = require '../src/qonsumer'

module.exports = (grunt) ->
  grunt.registerMultiTask 'qonsumer', 'configurable API crawler for scraping feeds to static files', ->
    options =
      options: @options
        log: yes

    options.files = @files

    qonsumer.init options, @async(), grunt
