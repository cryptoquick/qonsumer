qonsumer [![dependencies](http://img.shields.io/david/cryptoquick/qonsumer.svg?style=flat-square)](https://david-dm.org/cryptoquick/qonsumer) [![npm version Status](http://img.shields.io/npm/v/qonsumer.svg?style=flat-square)](https://www.npmjs.org/package/qonsumer)
========

qonsumer is a configurable API crawler, for scraping to static files. it is not meant for realtime apps; instead, it is meant for static consumption of api data. it will write the results of endpoint responses to static files for processing by other applications.

qonsumer can consume the following:

  - api endpoints in json format
  - api endpoints behind an authentication layer
    - currently supported formats: `hmac`
    - feel free to add your own
  - paginated records
  - other endpoints using rules and formatting from data in previously consumed endpoints
  - yaml stub files that contain data not defined in the api

qonsumer uses a configuration file to build a dependency tree. you must describe your api using tokens as wildcards. a token looks like this:

`(resource|selector)`

the selectors use JSONSelect, and their use is described here: [jsonselect.org](http://jsonselect.org/#tryit)

qonsumer is in early development stages, and its documentation is still in development. for the most up-to-date means of using qonsumer, check the following things:

  - see the repository for an example of a qonsumer.yaml.
  - type `qonsumer --help` for a list of all commands.
  - you will basically provide an input configuration yaml as the first argument, then a file to output those results as the second argument.

you will likely need to fork this project to make it suitable for your own needs. if you develop anything valuable, pull requests are gladly accepted. feature requests will also be considered; feel free to open an issue.

# install

`npm install -g qonsumer`

# run

example:

`qonsumer config.yaml output.json`

to log results instead of showing the default progress bar, use the `--verbose` or `-v` option.

# develop

for interested developers, fork or check out this repo, then run the grunt compile task, `grunt build`. coffeescript in `src` is compiled to `lib`, which can then be called by `./bin/qonsumer`. to test, in another terminal process, run `grunt server`, then run qonsumer on the example `qonsumer.yaml`.

pull requests for new functionality gladly accepted! all that's asked is that contributions are very specific in scope, remain in cofeescript, and roughly follow the format used in existing files.

# options

either in the the top level of your yaml document-- representing 'global'--, or within a host property, an `options` property may be defined, which can include these properties:

  - `max_concurrent` - qonsumer will attempt to limit the maxmimum number of concurrent requests to the same resource to this number. does not apply to number of requests to different resources.
  - `max_retries` - number of times to retry connection to a particular URL after a `500` or `404`
  - `delay` - number of milliseconds to wait between each request. this applies only between requests in the same resource, as requests to multiple resources can happen concurrently.
  - `timeout` - number of milliseconds to wait for a request to respond.

host config properties will override global properties.

# global config

an `env` property can be optionally defined globally. it will reach into the shell's environment and assign the values held by those variable names to the properties for use in other parts of the config, such as the host auth options.

```yaml
env:
  auth_email: API_EMAIL
  auth_password: API_PASSWORD
```

# host config

globally, a `hosts` property must be specified. hosts within that property can have any name, within reason, that signifies the host's shortened name. within that host name property, the following properties may be defined:

  - `protocol` - usually either `http` or `https`
  - `port` - usually either `80` or `443`; sometimes local development servers use `3000`
  - `hostname` - something like `api.example.com`, for example
  - `local` - if this is a local file, instead of a web resource, yaml and json files can be imported by defining a parent directory, and files within that directory can be specified as resources by defining `res` as their inner file path and name. this will override any web requests defined within that host. the property should be defined as a separate host, such as `stub`.
  - `res` - short for 'resource', this is a very important property. if `local` is defined, it refers to a file name under the `local` directory. otherwise, it refers to endpoints of the host provided in that host section. resources must be unique names, even between hosts, as each `res` can have cross-dependencies. dependencies are determined automatically, but special tokens are used to replace dynamic variables within the path. they follow the format of: `(resource|selector)`. selectors use [JSONSelect](http://jsonselect.org/#tryit).
  - `params` - static URL parameters (to be specific, the part of the URL that contains key-value pairs appended to the URL by a `?`, but before the `#`, also found by browser JS programmers in `window.location.search`) can be applied to a `res` by defining parameters individually by key-value pair. this is then automatically mapped to the URL.

# authentication

currently only a very specific form of HMAC authentication is supported.

a complete HMAC setup might appear like this:

```yaml
env:
  auth_email: STATIC_EMAIL
  auth_password: STATIC_PASSWORD

host:
  staging:
    protocol: https
    port: 443
    hostname: api.example.com

    res:
      posts: /posts
      comments: /comments/(posts|.comments .id)

    auth:
      method: POST
      protocol: https
      port: 443
      hostname: (host|hostname)
      path: /login

      post:
        user:
          email: (env|auth_email)
          password: (env|auth_password)

      hmac:
        hash_type: md5
        token_selector: .authentication_token
        format: (hmac|current_timestamp):(hmac|token)
        timestamp_format: X

      params:
        user_email: (env|auth_email)
        user_token: (hmac|hash)
        timestamp: (hmac|current_timestamp)
```

# extraction

after being saved, the results can also be processed and extracted if a global `extract` property is defined. within that property, JSON selectors are provided to applicable `res`, like so:

```yaml
extract:
  comments: .comments .timestamp
```

# whitelisting

ids can be whitelisted by resource type. this is done by providing a whitelist property on either the config or the grunt task.

# grunt task

this package can also be installed locally, and run with a grunt configuration, like this:

```coffeescript
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
```

a `qonsumer.yaml` is still required to configure resource descriptions.

# disclaimer

as a disclaimer, please don't use this for nefarious purposes. be kind to us API developers. qonsumer is meant to be a tool primarily for testing, and also to get around limitations of certain programs, such as static site generators.

qonsumer is copyright [Hunter Trujillo](https://twitter.com/cryptoquick), 2014-2015

built with friendship and magic at [PlaceWise Media](https://github.com/PlacewiseMedia)
