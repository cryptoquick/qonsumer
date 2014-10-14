fs = require 'fs'
path = require 'path'
mkdirp = require 'mkdirp'
yaml = require 'js-yaml'
select = require 'JSONSelect'
request = require 'request'
async = require 'async'
_ = require 'lodash'
_.mixin require 'lodash-deep'
yaml = require 'js-yaml'
traverse = require 'traverse'

module.exports =
  config:
    # defaults
    file: 'qonsume.yaml'
    dir: 'results/data.json'
    max: 4 # hardcoded hard limit on number of parallel connections

  global:
    res: {} # resources
    deps: {} # for async auto
    results: {}
    trees: {}

  init: (program) ->
    # configure
    @config.file = program.config? or program.args[0]? or @config.file
    @config.dir = program.results? or program.args[1]? or @config.dir

    # TODO detect if files are present
    if @config.file and @config.dir
      mkdirp path.dirname(@config.dir), (err) =>
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
      @download_all()
    catch e
      console.error e

  lexer: (template) ->
    matches = template.match /\(.*?\)/g
    results = {}
    resources = []
    keys = []

    if matches
      for pattern in matches
        str = pattern.substring(1, pattern.length - 1)
        spl = str.split('|')
        resource = spl[0]
        selector = spl[1]
        results[resource] = { resource, selector, pattern }
        resources.push results[resource]
        keys.push resource

    results._keys = keys
    results._resources = resources
    results._count = resources.length

    results

  render: (template, data, tree, selectors, deps, property_path) ->
    head = selectors.shift()
    tail = selectors

    unless head
      urls = []
      traverse(tree).forEach (val) ->
        if @isLeaf and (@level is property_path.length * 2 + 1) # ids
          url = template
          for i in [0...Math.floor(@path.length / 2)]
            inner_parent_key = @path[i * 2]
            pattern = deps[inner_parent_key].pattern
            path = @path.slice(0, (i + 1) * 2)
            path.push 'id'
            id = _.deepGet tree, path
            url = url.replace pattern, id
          urls.push
            id: id
            url: url
        val
      _.uniq urls, 'url'
    else
      for obj, i in data[head.resource]
        select.forEach head.selector, obj, (val) ->
          path = _.clone property_path
          if path.length # mustn't be root node
            path.push i
          path.push head.resource
          arr = _.deepGet(tree, path) or []
          arr.push
            id: val
          _.deepSet tree, path, arr
      property_path.push head.resource
      @render template, data, tree, tail, deps, property_path

  make_res: ->
    for host_name, host of @doc.hosts
      for res_name, res_path of host.res
        @global.res[res_name] =
          path: res_path
          host: host_name
          deps: @lexer res_path
          local: if host.local then host.local else no

  process_dependencies: ->
    cbf = (path, outer_cb, results) =>
      # 1. get resource
      res = @global.res[path]

      # 2. if resource is local, load and parse it
      if res.local
        file = fs.readFileSync res.local + res.path, 'utf8'
        if res.path.indexOf '.yaml' >= 0
          data = yaml.safeLoad file
        else if res.path.indexOf '.json' >= 0
          data = JSON.parse file
        else
          data = file
        outer_cb null, data
        return

      # 3. using the original url, build a set of urls to hit
      # console.log 'TWOFACE ARGS', res.path, '\n', results, '\n', res.deps._resources, '\n', res.deps
      if res.deps._count
        urls = @render res.path, results, {}, res.deps._resources, res.deps, []
      else
        urls = [
          url: res.path
        ]

      # 4. for every url, make a parallel async function in order to retrieve it
      inner_asyncs = []

      for url in urls when _.isArray urls
        inner_asyncs.push(
          do (url) =>
            (inner_cb) =>
              hostname = @doc.hosts[res.host].host or 'localhost'
              port = @doc.hosts[res.host].port or '80'
              uri = "http://#{hostname}:#{port}#{url.url}"

              request
                method: 'GET'
                uri: uri
                , (err, rsp, body) =>
                  if not err and rsp.statusCode is 200
                    console.log "GET #{uri} => 200 OK #{body.length} bytes"

                    if body.length
                      data = JSON.parse body
                      data.id = url.id if url.id
                    else
                      data = null

                    inner_cb null, data
                  else
                    inner_cb rsp.statusCode, null
        )

      async.parallelLimit inner_asyncs, @config.max, (err, inner_results) ->
        outer_cb err, inner_results

    for res_name, res of @global.res
      if res.deps._count
        auto_func = [
          do (res_name) ->
            (cb, results) ->
              cbf res_name, cb, results
        ]
        auto_deps = res.deps._keys.concat auto_func
        @global.deps[res_name] = auto_deps

      else
        @global.deps[res_name] =
          do (res_name) ->
            (cb) ->
              cbf res_name, cb

  download_all: ->
    # console.log @global.deps
    async.auto @global.deps, (err, results) =>
      unless err
        console.log 'Writing results...'
        fs.writeFileSync(@config.dir, JSON.stringify(results, null, 2), 'utf8')
        console.log 'Done!'
      else
        console.error err
