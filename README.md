qonsumer
--------

qonsumer is a nodejs api consumer. it is not meant for realtime apps; instead, it is meant for static consumption of api data. it will write the results of endpoint responses to static files for processing by other applications.

qonsumer can consume the following:

  - api endpoints in json format
  - api endpoints behind an authentication layer
    - currently supported formats: `hmac`
    - feel free to add your own
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
