# faking setImmediate for node < 0.9
require 'setimmediate'

glob = require 'glob'
fs = require 'fs'
protagonist = require 'protagonist'
async = require 'async'

logger = require './logger'
options = require './options'
Runner = require './transaction-runner'
applyConfiguration = require './apply-configuration'
handleRuntimeProblems = require './handle-runtime-problems'
blueprintAstToRuntime = require './blueprint-ast-to-runtime'
configureReporters = require './configure-reporters'

class Dredd
  constructor: (config) ->
    @tests = []
    @stats =
        tests: 0
        failures: 0
        errors: 0
        passes: 0
        skipped: 0
        start: 0
        end: 0
        duration: 0
    @configuration = applyConfiguration(config, @stats)
    configureReporters @configuration, @stats, @tests
    @runner = new Runner(@configuration)

  run: (callback) ->
    config = @configuration
    stats = @stats

    config.files = []

    async.each config.options.path, (globToExpand, globCallback) ->
      glob globToExpand, (err, match) ->
        globCallback err if err
        config.files = config.files.concat match
        globCallback()

    , (err) ->
      return callback(err, stats) if err
      return callback({message: "Blueprint file or files not found on path: '#{config.options.path}'"}, stats) if config.files.length == 0

      uniqueFiles = config.files.filter (item, pos) ->
        return config.files.indexOf(item) == pos

      config.files = uniqueFiles

      config.blueprintPath = config.files[0] # temporary till multifile processing

      fs.readFile config.blueprintPath, 'utf8', (loadingError, data) ->
        return callback(loadingError, stats) if loadingError

        reporterCount = config.emitter.listeners('start').length
        config.emitter.emit 'start', data, () ->
          reporterCount--
          if reporterCount is 0
            protagonist.parse data, blueprintParsingComplete

    blueprintParsingComplete = (protagonistError, result) =>
      return callback(protagonistError, config.reporter) if protagonistError

      if result['warnings'].length > 0
        for warning in result['warnings']
          message = 'Parser warning: ' + ' (' + warning.code + ') ' + warning.message
          for loc in warning['location']
            pos = loc.index + ':' + loc.length
            message = message + ' ' + pos
          logger.warn message

      runtime = blueprintAstToRuntime result['ast']
      runtimeError = handleRuntimeProblems runtime
      return callback(runtimeError, stats) if runtimeError

      @runner.run runtime['transactions'], () =>
        @transactionsComplete(callback)

  transactionsComplete: (callback) =>
    stats = @stats
    reporterCount = @configuration.emitter.listeners('end').length
    @configuration.emitter.emit 'end' , () ->
      reporterCount--
      if reporterCount is 0
        callback(null, stats)

module.exports = Dredd
module.exports.options = options
