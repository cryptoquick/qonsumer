traverse = require 'traverse'

lexer = (template) ->
  matches = template.toString().match /\(.*?\)/g
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

apply_lexer = (template, resources, data) =>
  unless template
    return null
  tokens = lexer template
  if tokens._count
    for token in tokens._resources
      if token.resource in resources
        template = template.replace token.pattern, data[token.selector]
  template

apply_many = (obj, resources, data) ->
  traverse(obj).forEach (o) ->
    if @isLeaf
      @update apply_lexer o, resources, data

module.exports = { lexer, apply_lexer, apply_many }
