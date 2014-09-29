module.exports = (grunt) ->
  config =
    pkg: grunt.file.readJSON 'package.json'

    coffee:
      build:
        options:
          bare: yes
        expand: yes
        flatten: yes
        cwd: 'src'
        src: '*.coffee'
        dest: 'lib'
        ext: '.js'

    file_append:
      build:
        files:
          'bin/qonsume':
            prepend: '#!/usr/bin/env node\n'
            input: 'lib/index.js'

    chmod:
      options:
        mode: '755'
      build:
        src: ['bin/qonsume']

    watch:
      watch:
        files: ['src/*']
        tasks: ['build']
        options:
          spawn: no
          atBegin: yes

  grunt.initConfig config

  grunt.loadNpmTasks task for task of config.pkg.devDependencies when task.indexOf 'grunt-' >= 0

  grunt.registerTask 'build', [
    'coffee'
    'file_append'
    'chmod'
  ]
