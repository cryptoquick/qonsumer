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
progress = require 'awesome-progress'
lexic = require './lexic'

print =
  start: chalk.cyan
  error: chalk.bold.red
  warning: chalk.yellow
  success: chalk.green
  greatSuccess: chalk.bold.magenta

module.exports =
  config:
    # defaults
    file: 'qonsumer.yaml'
    dir: 'results/data.json'
    max: 2 # hard limit on number of parallel connections
    retries: 4
    log: no

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
    @config.log = !!program.verbose

    # progress bar
    unless @config.log
      @global.bar = progress(1)

    # TODO detect if files are present
    if @config.file and @config.dir
      mkdirp path.dirname(@config.dir), (err) =>
        if err
          console.error print.error err if @config.log
        else
          console.log print.start "#{@config.file} => #{@config.dir}" if @config.log
        @run()

    else
      unless @config.file
        console.log print.warning 'no config file passed' if @config.log
      unless @config.dir
        console.log print.warning 'no results directory passed' if @config.log

      console.log print.error 'there was an error. use the --help option for more information.' if @config.log

  run: ->
    try
      @doc = yaml.safeLoad(fs.readFileSync(@config.file, 'utf8'))
      cb = =>
        @make_res()
        @process_dependencies()
        @download_all()
      @preconfig(cb)
    catch e
      console.error print.error e if @config.log

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
      log = @config.log
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
            console.log print.start "AUTH #{method} #{uri}" if log

            needle.request(
              method,
              uri,
              auth.post,
              {
                rejectUnauthorized: no
                follow: yes
              },
              (err, resp) ->
                unless err
                  console.log print.success "#{resp.statusCode} #{resp.statusMessage or ''} #{resp.bytes} bytes" if log

                  if resp.body instanceof Buffer
                    data = JSON.parse resp.body.toString()
                  else
                    data = resp.body

                  token = select.match auth.hmac.token_selector, data

                  if token.length
                    host.options.auth.hmac.token = token[0]
                  else
                    console.error print.error 'access token not found. response was...', data if log
                  inner_cb null, data
                else
                  console.error print.error 'AUTH ERROR', err if log
                  inner_cb err, null
            )
      )

    if auth_tasks.length
      async.parallelLimit auth_tasks, @config.max, (err, results) ->
        if err
          console.error print.error err if @config.log
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
        console.error print.error 'there is no auth token for this host' if @config.log

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

      opts = _.extend @doc.options or {}, host.options or {}

      for url in urls when _.isArray urls
        request = do (url) =>
          (inner_cb, paged_data, runs, offset, new_url) =>
            url = new_url or url
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

            params = auth_params or {}
            params = _.extend params, host.params[url.name] if host.params?[url.name]

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

            console.log print.start "GET #{uri}" if @config.log

            needle.request(
              'GET',
              uri,
              params,
              {
                rejectUnauthorized: no
                follow: yes
                timeout: opts.timeout or 10000
              },
              (err, resp) =>
                unless err or resp.statusCode is 500 or resp.statusCode is 404
                  if pag
                    page = "... records #{offset} - #{offset + pag.limit}"
                  else
                    page = ""

                  console.log print.success "#{resp.statusCode} #{resp.statusMessage or ''} #{url.url} #{resp.bytes} bytes#{page}" if @config.log

                  if resp.body instanceof Buffer
                    data = JSON.parse resp.body.toString()
                  else
                    data = resp.body

                  if resp.bytes
                    data.id = url.id if url.id
                  else
                    data = null

                  # pagination
                  if pag and (select.match(pag.selector, data).length is pag.limit)
                    offset += pag.limit
                    paged_data.push data
                    _.delay ->
                      @global.bar.total++ unless @config.log
                      request inner_cb, 0, offset, paged_data
                    , opts.delay or 100
                  else # standard single request
                    if paged_data.length
                      paged_data.push data
                      data = paged_data
                    @global.bar.op() unless @config.log
                    inner_cb null, data
                else # there was an error...
                  error = err or resp.statusCode
                  unless runs >= retries
                    console.log print.warning "WARNING #{error} ... retrying #{url.url}, try \##{runs + 1}" if @config.log
                    _.delay =>
                      runs++
                      request inner_cb, paged_data, runs, offset, url
                    , opts.delay or 100
                  else # give up
                    console.log print.error "SKIPPED #{error} #{url.url}" if @config.log
                    inner_cb null, { error }
                    unless @config.log
                      @global.bar.op
                        errors: 1
            )

        if opts.delay
          delayed_request = (inner_cb, results) ->
            _.delay request, opts.delay, inner_cb, results

        inner_asyncs.push request or delayed_request

      @global.bar.total += inner_asyncs.length unless @config.log

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
    async.auto(@global.deps, (err, results) =>
      @global.time_ended = new Date()
      duration = moment(@global.time_started).twix(@global.time_ended).humanizeLength()

      unless err
        console.log print.success 'Writing results...' if @config.log
        fs.writeFileSync(@config.dir, JSON.stringify(results, null, 2), 'utf8')
      else
        console.error print.error err if @config.log

      console.log print.greatSuccess 'Done!' if @config.log
      console.log "qonsumer took #{duration} to run." if @config.log

      @global.bar.op() unless @config.log

      @post_process()
    , @config.max)

  post_process: ->
    if @doc.extract
      json = fs.readFileSync @config.dir, 'utf8'
      data = JSON.parse json
      results = {}

      for key, obj of data
        if @doc.extract[key]
          results[key] = select.match @doc.extract[key], obj

      fs.writeFileSync("#{@config.dir}.extracts.json", JSON.stringify(results, null, 2), 'utf8')

      console.log "data extracted." if @config.log
