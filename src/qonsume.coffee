fs = require 'fs'
path = require 'path'
mkdirp = require 'mkdirp'
yaml = require 'js-yaml'
select = require 'JSONSelect'
needle = require 'needle'
async = require 'async'
_ = require 'lodash'
_.mixin require 'lodash-deep'
yaml = require 'js-yaml'
traverse = require 'traverse'
crypto = require 'crypto'
moment = require 'moment'
require 'twix'
lexic = require './lexic'

module.exports =
  config:
    # defaults
    file: 'qonsume.yaml'
    dir: 'results/data.json'
    max: 2 # hardcoded hard limit on number of parallel connections

  global:
    res: {} # resources
    deps: {} # for async auto
    results: {}
    trees: {}

  init: (program) ->
    @global.time_started = new Date()

    # configure
    @config.file = program.config or program.args[0] or @config.file
    @config.dir = program.results or program.args[1] or @config.dir

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
      cb = =>
        @make_res()
        @process_dependencies()
        @download_all()
      @preconfig(cb)
    catch e
      console.error e

  preconfig: (cb) ->
    if @doc.env
      @config.env = {}
      for k, v of @doc.env
        @config.env[k] = process.env[v]

    if @doc.options?.max_concurrent
      @config.max = @doc.options.max_concurrent

    auth_tasks = []
    for host_name, host of @doc.hosts
      auth = host.options?.auth
      if auth
        auth_tasks.push(
          (inner_cb) =>
            protocol = auth.protocol or 'https'
            hostname = lexic.apply_lexer auth.hostname, ['host'], host
            port = lexic.apply_lexer(auth.port, ['port'], host) or '80'
            path = auth.path or ''
            method = auth.method or 'POST'

            lexic.apply_many auth.post, ['env'], @config.env

            uri = "#{protocol}://#{hostname}:#{port}#{path}"
            console.log "AUTH #{method} #{uri}"

            needle.request(
              method,
              uri,
              auth.post,
              {
                rejectUnauthorized: no
              },
              (err, resp) ->
                unless err
                  console.log "#{resp.statusCode} #{resp.statusMessage} #{resp.bytes} bytes"

                  if resp.body instanceof Buffer
                    data = JSON.parse resp.body.toString()
                  else
                    data = resp.body

                  token = select.match auth.hmac.token_selector, data

                  if token.length
                    host.options.auth.hmac.token = token[0]
                  else
                    console.error 'access token not found. response was...', data
                  inner_cb null, data
                else
                  console.error 'AUTH ERROR', err
                  inner_cb err, null
            )
      )

    if auth_tasks.length
      async.parallelLimit auth_tasks, @config.max, (err, results) ->
        if err
          console.error err
          throw err
        else
          cb()
    else
      cb()

  handle_auth: (host_name) ->
    host = @doc.hosts[host_name]
    hmac = host.options.auth.hmac

    if hmac
      unless hmac.token
        console.error 'there is no auth token for this host'

      if hmac.timestamp_format
        hmac.current_timestamp = moment().format hmac.timestamp_format

      str = lexic.apply_lexer hmac.format, ['hmac'], hmac
      shasum = crypto.createHash hmac.hash_type
      shasum.update str
      hmac.hash = shasum.digest 'hex'
      hmac.hash

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
      datum = data[head.resource]
      unless _.isArray datum
        datum = [datum]
      for obj, i in datum
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
          deps: lexic.lexer res_path
          local: if host.local then host.local else no

  process_dependencies: ->
    cbf = (path, outer_cb, results) =>
      # 1. get resource
      res = @global.res[path]
      host = @doc.hosts[res.host]

      # 2. if resource is local, load and parse it
      if host.local
        file = fs.readFileSync res.local + res.path, 'utf8'
        if res.path.indexOf '.yaml' >= 0
          data = yaml.safeLoad file
        else if res.path.indexOf '.json' >= 0
          data = JSON.parse file
        else
          data = file
        console.log "LOCAL #{res.local}#{res.path}"
        outer_cb null, data
        return

      # 3. using the original url, build a set of urls to hit
      if res.deps._count
        urls = @render res.path, results, {}, res.deps._resources, res.deps, []
      else
        urls = [
          url: res.path
        ]

      # 4. for every url, make a parallel async function in order to retrieve it
      inner_asyncs = []

      for url in urls when _.isArray urls
        request = do (url) =>
          (inner_cb) =>
            host = @doc.hosts[res.host]
            hostname = host.hostname or 'localhost'
            port = host.port or '80'
            protocol = host.protocol or 'http'

            uri = "#{protocol}://#{hostname}:#{port}#{url.url}"

            auth_params = _.clone host.options?.auth?.params

            if auth_params
              @handle_auth res.host
              lexic.apply_many auth_params, ['env'], @config.env
              lexic.apply_many auth_params, ['hmac'], host.options.auth.hmac

            params = auth_params or {} # TODO extend params

            console.log "GET #{uri}"

            needle.request(
              'GET',
              uri,
              params,
              {
                rejectUnauthorized: no
              },
              (err, resp) ->
                unless err or resp.statusCode is 500
                  console.log "#{resp.statusCode} #{resp.statusMessage} #{url.url} #{resp.bytes} bytes"

                  if resp.body instanceof Buffer
                    data = JSON.parse resp.body.toString()
                  else
                    data = resp.body

                  if resp.bytes
                    data.id = url.id if url.id
                  else
                    data = null

                  inner_cb null, data
                else
                  error = err or resp.statusCode
                  console.log "ERROR #{error}\nretrying..."
                  request inner_cb
                  # inner_cb err, null
            )
        inner_asyncs.push request

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
    async.auto @global.deps, (err, results) =>
      @global.time_ended = new Date()
      duration = moment(@global.time_started).twix(@global.time_ended).humanizeLength()

      unless err
        console.log 'Writing results...'
        fs.writeFileSync(@config.dir, JSON.stringify(results, null, 2), 'utf8')
      else
        console.error err

      console.log 'Done!'
      console.log "qonsume took #{duration} to run."
