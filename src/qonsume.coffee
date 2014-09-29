mkdirp = require 'mkdirp'
yaml = require 'js-yaml'
fs = require 'fs'
select = require 'JSONSelect'
request = require 'request'
DepGraph = require('dependency-graph').DepGraph

module.exports =
  config:
    # defaults
    file: './qonsume.yaml'
    dir: './results'

  global:
    res: {}

  init: (program) ->
    # configure
    @config.file = program.config? or program.args[0]? or @config.file
    @config.dir = program.results? or program.args[1]? or @config.dir

    if @config.file and @config.dir
      mkdirp @config.dir, (err) =>
        if err
          console.error err
        else
          console.log "#{@config.file} => #{@config.dir}"
          @run()

    else
      unless @config.file
        console.log 'no config file passed'
      unless @config.dir
        console.log 'no results directory passed'

      console.log 'there was an error. use the --help option for more information.'

  run: ->
    try
      @doc = yaml.safeLoad(fs.readFileSync(@config.file, 'utf8'))
      @make_res()
      @process_dependencies()
      @download_dependencies()
    catch e
      console.error e

  make_res: ->
    for host_name, host of @doc.hosts
      for res_name, res_path of host.res
        @global.res["#{host_name}.#{res_name}"] =
          path: res_path
          host: host_name

  add_dependency: (name, dep) ->
    @graph.addNode name
    @graph.addDependency name, dep if dep

  process_dependencies: ->
    @graph = new DepGraph()

    for res_name of @global.res
      # select.match path, obj
      deps = res_name.match(/\(.*?\)/g)

      if deps
        for dep in deps
          console.log dep
          res_dep = dep.substring(1, dep.length - 1).split(' ')[0]
          @add_dependency res_name, res_dep
      else
        @add_dependency res_name

  download_dependencies: ->
    order = @graph.overallOrder()
    console.log "getting the following resources, in the following order:\n#{order.join('\n')}\n"

    for res_name in order
      res = @global.res[res_name]
      host = @doc.hosts[res.host]
      console.log res_name, res
      console.log "download: #{host.host}#{res.path}"
