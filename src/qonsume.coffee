mkdirp = require 'mkdirp'
yaml = require 'js-yaml'
fs = require 'fs'
select = require 'JSONSelect'
request = require 'request'
async = require 'async'
yaml = require 'js-yaml'

module.exports =
  config:
    # defaults
    file: './qonsume.yaml'
    dir: './results'

  global:
    res: {} # resources
    deps: {} # for async auto
    results: {}
    deps: {}

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
      @download_all()
    catch e
      console.error e

  make_res: ->
    for host_name, host of @doc.hosts
      for res_name, res_path of host.res
        deps = res_path.match(/\(.*?\)/g)
        if deps
          formatted_deps = [dep.substring(1, dep.length - 1).split('|')[0] for dep in deps][0]
          selectors_obj = deps.reduce (prv, val, i) ->
              prv[formatted_deps[i]] =
                full: val
                sel: val.substring(1, val.length - 1).split('|')[1]
              prv
            , {}
        else
          formatted_deps = []
          selectors_obj = {}

        @global.res[res_name] =
          path: res_path
          host: host_name
          deps: formatted_deps
          sels: selectors_obj
          local: if host.local then host.local else no

  process_dependencies: ->
    cbf = (path, outer_cb, results) =>
      # 1. get resource
      res = @global.res[path]

      # 2. if resource is local, load and parse it
      if res.local
        fs.readFile res.local + res.path, (file) ->
          if res.local.indexOf '.yaml'
            data = yaml.safeLoad file
          else if res.local.indexOf '.json'
            data = JSON.parse file
          else
            data = file
          outer_cb null, data
          , 'utf8'
        return

      # 3. using the original url, build a set of urls to hit
      orig_url = res.path
      urls = []

      if res.deps.length
        for dep_name in res.deps
          url = orig_url + ''
          selector = res.sels[dep_name]
          matches = select.match selector.sel, results[dep_name]

          console.log 'DEBUG', url, dep_name, selector, matches

          for match in matches
            urls.push url.replace(selector.full, match)
            # console.log url
            # urls.push url
      else
        urls.push orig_url

      # 4. TODO
      console.log urls

      # 5. for every url, make a parallel async function in order to retrieve it
      inner_asyncs = []

      for url in urls
        inner_asyncs.push (inner_cb) =>
          hostname = @doc.hosts[res.host].host or 'localhost'
          port = @doc.hosts[res.host].port or '80'
          uri = "http://#{hostname}:#{port}#{url}"
          console.log "Hitting #{uri}"

          request
            method: 'GET'
            uri: uri
            , (err, rsp, body) =>
              if not err and rsp.statusCode is 200
                console.log "200 OK #{body.length} bytes"
                inner_cb null, JSON.parse body
              else
                inner_cb rsp.statusCode, null

      async.parallel inner_asyncs, (err, results) ->
        outer_cb err, results

    for res_name, res of @global.res
      if res.deps.length
        auto_func = [
          do (res_name) ->
            (cb, results) ->
              cbf res_name, cb, results
        ]
        auto_deps = res.deps.concat auto_func
        @global.deps[res_name] = auto_deps

      else
        @global.deps[res_name] =
          do (res_name) ->
            (cb) ->
              cbf res_name, cb

  download_all: ->
    # console.log @global.deps
    console.log @global.deps
    async.auto @global.deps, (err, results) ->
      unless err
        console.log results
      else
        console.error err
