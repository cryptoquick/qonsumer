qonsume is a nodejs api consumer. it is not meant for realtime apps; instead, it is meant for static consumption of api data. it will write the results of endpoint responses to files for processing by other applications. although it can consume restful interfaces, its only http activity is an http 'get'.

qonsume can consume the following:

  - api endpoints in json format
  - api endpoints behind an authentication layer
  - other endpoints using rules and formatting from data in previously consumed endpoints
  - yaml stub files that contain data not defined in the api

qonsume uses a configuration file to build a dependency tree.

qonsume is in early development stages, and its documentation is still in development. for the most up-to-date means of using qonsume, check the following things:

  - see the repository for an example of a qonsume.yaml.
  - type `qonsume help` for a list of all commands.

# problem?

if you see the error: `Error: One of the nodes does not exist`:
routes that depend on other routes should be defined after the other routes have been defined.
