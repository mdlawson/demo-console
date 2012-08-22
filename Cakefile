flour  = require 'flour'
{exec} = require 'child_process'
path   = require 'path'


task 'build:src', ->
  compile 'src/console.coffee','lib/console.js'
  minify 'lib/console.js','lib/console.min.js'

task 'serve:demo', ->
  test = require "./demo/server"

task 'watch', ->
  watch 'src/console.coffee', -> invoke 'build:src'
  invoke 'serve:demo'
