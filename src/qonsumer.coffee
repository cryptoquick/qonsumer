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
chalk = require 'chalk'
lexic = require './lexic'

print =
  start: chalk.black.bgCyan
  error: chalk.bold.white.bgRed
  warning: chalk.black.bgYellow
  success: chalk.black.bgGreen
  greatSuccess: chalk.bold.white.bgMagenta

module.exports =
  config:
    # defaults
    file: 'qonsumer.yaml'
    dir: 'results/data.json'
    max: 2 # hard limit on number of parallel connections
    retries: 4

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
          console.error print.error err
        else
          console.log print.start "#{@config.file} => #{@config.dir}"
          @run()

    else
      unless @config.file
        console.log print.warning 'no config file passed'
      unless @config.dir
        console.log print.warning 'no results directory passed'

      console.log print.error 'there was an error. use the --help option for more information.'

  run: ->
    try
      @doc = yaml.safeLoad(fs.readFileSync(@config.file, 'utf8'))
      cb = =>
        @make_res()
        @process_dependencies()
        @download_all()
      @preconfig(cb)
    catch e
      console.error print.error e

  preconfig: (cb) ->
    if @doc.env
      @config.env = {}
      for k, v of @doc.env
        @config.env[k] = process.env[v]

    if @doc.options?.max_concurrent
      @config.max = @doc.options.max_concurrent

    if @doc.options?.max_retries
      @config.retries = @doc.options.max_retries

    auth_tasks = []
    for host_name, host of @doc.hosts
      auth = host.options?.auth
      if auth
        auth_tasks.push(
          (inner_cb) =>
            protocol = auth.protocol or 'https'
            hostname = lexic.apply_lexer auth.hostname, ['host'], host
            port = lexic.apply_lexer(auth.port, ['port'], host) or ''
            path = auth.path or ''
            method = auth.method or 'POST'

            lexic.apply_many auth.post, ['env'], @config.env

            uri = "#{protocol}://#{hostname}:#{port}#{path}"
            console.log print.start "AUTH #{method} #{uri}"

            needle.request(
              method,
              uri,
              auth.post,
              {
                rejectUnauthorized: no
              },
              (err, resp) ->
                unless err
                  console.log print.success "#{resp.statusCode} #{resp.statusMessage} #{resp.bytes} bytes"

                  if resp.body instanceof Buffer
                    data = JSON.parse resp.body.toString()
                  else
                    data = resp.body

                  token = select.match auth.hmac.token_selector, data

                  if token.length
                    host.options.auth.hmac.token = token[0]
                  else
                    console.error print.error 'access token not found. response was...', data
                  inner_cb null, data
                else
                  console.error print.error 'AUTH ERROR', err
                  inner_cb err, null
            )
      )

    if auth_tasks.length
      async.parallelLimit auth_tasks, @config.max, (err, results) ->
        if err
          console.error print.error err
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
        console.error print.error 'there is no auth token for this host'

      if hmac.timestamp_format
        hmac.current_timestamp = moment().format hmac.timestamp_format

      str = lexic.apply_lexer hmac.format, ['hmac'], hmac
      shasum = crypto.createHash hmac.hash_type
      shasum.update str
      hmac.hash = shasum.digest 'hex'
      hmac.hash

  render: (res, data, tree, selectors, property_path) ->
    head = selectors.shift()
    tail = selectors
    template = res.path
    deps = res.deps
    res_name = res.name

    unless head
      urls = []
      traverse(tree).forEach (val) ->
        if @isLeaf and (@level is property_path.length * 2 + 1) # ids
          url = template
          for i in [0...Math.floor(@path.length / 2)]
            # inner_parent_key = @path[i * 2]
            path = @path.slice(0, (i + 1) * 2)
            id = _.deepGet tree, path.concat 'id'
            res = _.deepGet tree, path.concat 'res'
            pattern = deps[res].pattern
            url = url.replace pattern, id
          urls.push
            id: id
            url: url
            name: res_name
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
            res: head.resource
          _.deepSet tree, path, arr
      property_path.push head.resource
      @render res, data, tree, tail, property_path

  make_res: ->
    for host_name, host of @doc.hosts
      for res_name, res_path of host.res
        @global.res[res_name] =
          name: res_name
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
        console.log print.success "LOCAL #{res.local}#{res.path}"
        outer_cb null, data
        return

      # 3. using the original url, build a set of urls to hit
      if res.deps._count
        urls = @render res, results, {}, res.deps._resources, []
      else
        urls = [
          url: res.path
          name: res.name
        ]

      # 4. for every url, make a parallel async function in order to retrieve it
      inner_asyncs = []

      for url in urls when _.isArray urls
        request = do (url) =>
          (inner_cb, runs, offset, paged_data) =>
            runs = runs or 0
            host = @doc.hosts[res.host]
            hostname = host.hostname or 'localhost'
            port = host.port or ''
            protocol = host.protocol or 'http'

            uri = "#{protocol}://#{hostname}:#{port}#{url.url}"

            auth_params = _.clone host.options?.auth?.params

            if auth_params
              @handle_auth res.host
              lexic.apply_many auth_params, ['env'], @config.env
              lexic.apply_many auth_params, ['hmac'], host.options.auth.hmac

            params = auth_params or {} # TODO extend params

            pag = host.pagination?[url.name]
            offset = offset or 0
            paged_data = paged_data or []

            if pag
              pag_params = {}
              if pag.params.limit_param
                pag_params[pag.params.limit_param] = pag.limit
              if pag.params.offset_param
                pag_params[pag.params.offset_param] = offset
              params = _.extend params, pag_params

            retries = @config.retries

            console.log print.start "GET #{uri}"

            needle.request(
              'GET',
              uri,
              params,
              {
                rejectUnauthorized: no
              },
              (err, resp) ->
                unless err or resp.statusCode is 500 or resp.statusCode is 404
                  if pag
                    page = "... records #{offset} - #{offset + pag.limit}"
                  else
                    page = ""

                  console.log print.success "#{resp.statusCode} #{resp.statusMessage} #{url.url} #{resp.bytes} bytes#{page}"

                  if resp.body instanceof Buffer
                    data = JSON.parse resp.body.toString()
                  else
                    data = resp.body

                  if resp.bytes
                    data.id = url.id if url.id
                  else
                    data = null

                  if pag and (select.match(pag.selector, data).length is pag.limit)
                    offset += pag.limit
                    paged_data.push data
                    request inner_cb, 0, offset, paged_data
                  else
                    if paged_data.length
                      paged_data.push data
                      data = paged_data
                    inner_cb null, data
                else
                  error = err or resp.statusCode
                  console.log print.warning "WARNING #{error} ... retrying #{url.url}"
                  unless runs >= retries
                    runs++
                    request inner_cb, runs, offset, paged_data
                  else
                    console.log print.error "SKIPPED #{error} #{url.url}"
                    inner_cb null, { error }
            )
        inner_asyncs.push request

      async.parallelLimit inner_asyncs, @config.max, (err, inner_results) ->
        outer_cb err, inner_results

    for res_name, res of @global.res
      if res.deps._count
        auto_func =
          do (res_name) ->
            (auto_cb, results) ->
              cbf res_name, auto_cb, results
        auto_deps = res.deps._keys.concat [auto_func]
        @global.deps[res_name] = auto_deps

      else
        @global.deps[res_name] =
          do (res_name) ->
            (auto_cb) ->
              cbf res_name, auto_cb

  download_all: ->
    async.auto @global.deps, (err, results) =>
      @global.time_ended = new Date()
      duration = moment(@global.time_started).twix(@global.time_ended).humanizeLength()

      unless err
        console.log print.success 'Writing results...'
        fs.writeFileSync(@config.dir, JSON.stringify(results, null, 2), 'utf8')
      else
        console.error print.error err

      console.log print.greatSuccess 'Done!'
      console.log "qonsumer took #{duration} to run."
