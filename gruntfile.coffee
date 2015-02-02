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
          'bin/qonsumer':
            prepend: '#!/usr/bin/env node\n'
            input: 'lib/index.js'

    chmod:
      options:
        mode: '755'
      build:
        src: ['bin/qonsumer']

    watch:
      watch:
        files: ['src/*']
        tasks: ['default']
        options:
          spawn: no
          atBegin: yes

    stubby:
      server:
        options:
          stubs: 3030
          persistent: yes
          relativeFilesPath: yes
        files: [
          src: 'test/live/endpoints.yaml'
        ]

    qonsumer:
      test:
        options:
          whitelist:
            articles: [1, 3]
          log: yes
        files: [
          src: 'qonsumer.yaml'
          dest: 'results/data.json'
        ]

  grunt.initConfig config

  grunt.loadNpmTasks task for task of config.pkg.devDependencies when task.indexOf 'grunt-' is 0

  grunt.loadTasks 'tasks'

  grunt.registerTask 'default', [
    'coffee'
    'file_append'
    'chmod'
  ]

  grunt.registerTask 'test', ['stubby']
