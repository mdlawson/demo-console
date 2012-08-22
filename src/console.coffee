window.demoCon = {}
  
###
The Sandbox.Model

Takes care of command evaluation, history and persistence via localStorage adapter
###
class demoCon.History extends Backbone.Model
    
    defaults:
      history: []

    initialize: ->
      _.bindAll this
      
      @evaluator = @js

      # Attempt to fetch the Model from localStorage
      @fetch()
      
      # When the Model is destroyed (eg. via ':clear'), erase the current history as well
      @bind "destroy", (model) ->
        model.set history: []


    
    # The Sandbox Model tries to use the localStorage adapter to save the command history
    localStorage: new Backbone.LocalStorage("DemoConsole")
    
    # Parser for restoring the Model's state
    # Backbone.localStorage adapter stores a collecti`on, so grab the first 'model'
    parse: (data) ->
      
      # `parse` also fires when doing a save, so just return the model for that
      return data  if not _.isArray(data) or data.length < 1 or not data[0]
      
      # Hide the saved command history, so that they don't show up in output,
      # and delete the results and classes from each, because they won't be needed
      data[0].history = _.map(data[0].history, (command) ->
        command._hidden = true
        delete command.result  if command.result
        delete command._class  if command._class
        command
      )

      data[0]

    
    stringify: (o, simple, visited) ->
      json = ""
      i = undefined
      vi = undefined
      type = ""
      parts = []
      names = []
      circular = false
      visited = visited or []
      sortci = (a, b) -> (if a.toLowerCase() < b.toLowerCase() then -1 else 1)
      try
        type = ({}).toString.call(o)
      catch e # only happens when typeof is protected (...randomly)
        type = "[object Object]"
      
      # check for circular references
      vi = 0
      while vi < visited.length
        if o is visited[vi]
          circular = true
          break
        vi++
      if circular
        json = "[circular]"
      else if type is "[object String]"
        json = "\"" + o.replace(/"/g, "\\\"") + "\""
      else if type is "[object Array]"
        visited.push o
        json = "["
        i = 0
        while i < o.length
          parts.push @stringify(o[i], simple, visited)
          i++
        json += parts.join(", ") + "]"
        json
      else if type is "[object Object]"
        visited.push o
        json = "{"
        for i of o
          names.push i
        names.sort sortci
        i = 0
        while i < names.length
          parts.push @stringify(names[i], `undefined`, visited) + ": " + @stringify(o[names[i]], simple, visited)
          i++
        json += parts.join(", ") + "}"
      else if type is "[object Number]"
        json = o + ""
      else if type is "[object Boolean]"
        json = (if o then "true" else "false")
      else if type is "[object Function]"
        json = o.toString()
      else if o is null
        json = "null"
      else if o is `undefined`
        json = "undefined"
      else if simple is `undefined`
        visited.push o
        json = type + "{\n"
        for i of o
          names.push i
        names.sort sortci
        i = 0
        while i < names.length
          try
            parts.push names[i] + ": " + @stringify(o[names[i]], true, visited) # safety from max stack
          catch e
            e.name is "NS_ERROR_NOT_IMPLEMENTED"
          i++
        
        # do nothing - not sure it's useful to show this error when the variable is protected
        # parts.push(names[i] + ': NS_ERROR_NOT_IMPLEMENTED');
        json += parts.join(",\n") + "\n}"
      else
        try
          json = o + "" # should look like an object
      json
    
    # Adds a new item to the history
    addHistory: (item) ->
      history = @get("history")
      
      # Tidy up the item's result
      item.result = "\"" + item.result.toString().replace(/"/g, "\\\"") + "\""  if _.isString(item.result)
      item.result = item.result.toString().replace(/"/g, "\\\"")  if _.isFunction(item.result)
      item.result = @stringify(item.result).replace(/"/g, "\\\"")  if _.isObject(item.result)
      item.result = "undefined"  if _.isUndefined(item.result)
      
      # Add the command and result to the history
      history.push item
      
      # Update the history state and save the model
      @save(history: history)
      @trigger 'change',@,history
      this

    
    # One way of loading scripts into the document or the sandboxed iframe:
    load: (src) ->
      script = document.createElement("script")
      script.type = "text/javascript"
      script.src = src
     	document.body.appendChild script

    
    # Evaluate a command and save it to history
    evaluate: (command) ->
      return false unless command
      item = 
        command: command
      
      # Evaluate the command and store the eval result, adding some basic classes for syntax-highlighting
      try
        item.result = @evaluator command
        item._class = "undefined"  if _.isUndefined(item.result)
        item._class = "number"  if _.isNumber(item.result)
        item._class = "string"  if _.isString(item.result)
      catch error
        item.result = error.toString()
        item._class = "error"
      
      # Add the item to the history
      @addHistory item

    js: (command) -> eval.call(window,command)
    coffee: (command) -> CoffeeScript.eval.call(window,command)
  
###
The Sandbox.View

Defers to the Sandbox.Model for history, evaluation and persistence
Takes care of all the rendering, controls, events and special commands
###
class demoCon.View extends Backbone.View

  initialize: (opts) ->
    _.bindAll this
    
    # Set up the history state (the up/down access to command history)
    @model = new demoCon.History
    @historyState = @model.get("history").length
    @currentHistory = ""
    
    # Set up the View Options
    @resultPrefix = opts.resultPrefix or "  => "
    @tabCharacter = opts.tabCharacter or "\t"
    @placeholder = opts.placeholder or "// type some javascript and hit enter (:help for info)"
    @helpText = opts.helpText or "type javascript commands into the console, hit enter to evaluate. \n[up/down] to scroll through history, ':clear' to reset it. \n[alt + return/up/down] for returns and multi-line editing.\n':coffee' tells the console to evaluate input as coffeescript,\n':js' tells it you are using js again"
    
    # Bind to the model's change event to update the View
    @model.bind "change", @update
    
    # Render the textarea
    @render()

  events:
    "keydown textarea"  : "keyDown"
    "keyup textarea"    : "keyUp"
    "click .output"     : "focus"
  
  # The templating functions for the View and each history item
  template: _.template($("#tplSandbox").html())
  format: _.template($("#tplCommand").html())
  
  # Renders the Sandbox View initially and stores references to the elements
  render: ->
    $el = $(@el)
    $el.html @template(placeholder: @placeholder)
    @textarea = $el.find("textarea")
    @output = $el.find(".output")
    this

  
  # Updates the Sandbox View, redrawing the output and checking the input's value
  update: ->
    
    # Reduce the Model's history into HTML, using the command format templating function
    @output.html _.reduce(@model.get("history"), (memo, command) ->
      memo + @format(
        _hidden: command._hidden
        _class: command._class
        command: @toEscaped(command.command)
        result: @toEscaped(command.result)
      )
    , "", this)
    
    # Set the textarea to the value of the currently selected history item
    # Update the textarea's `rows` attribute, as history items may be multiple lines
    @textarea.val(@currentHistory).attr "rows", @currentHistory.split("\n").length
    
    # Scroll the output to the bottom, so that new commands are visible
    @output.scrollTop @output[0].scrollHeight - @output.height()

  
  # Manually set the value in the sandbox textarea and focus it ready to submit:
  setValue: (command) ->
    @currentHistory = command
    @update()
    @setCaret @textarea.val().length
    @textarea.focus()
    false

  
  # Returns the index of the cursor inside the textarea
  getCaret: ->
    if @textarea[0].selectionStart
      return @textarea[0].selectionStart
    # If nothing else, assume index 0
    0

  
  # Sets the cursor position inside the textarea (not IE, afaik)
  setCaret: (index) ->
    @textarea[0].selectionStart = index
    @textarea[0].selectionEnd = index

  
  # Escapes a string so that it can be safely html()'ed into the output:
  toEscaped: (string) ->
    String(string).replace(/\\"/g, "\"").replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/'/g, "&#39;").replace(/</g, "&lt;").replace />/g, "&gt;"

  
  # Focuses the input textarea
  focus: (e) ->
    e.preventDefault()
    @textarea.focus()
    false

  
  # The keydown handler, that controls all the input
  keyDown: (e) ->
    
    # Register shift, control and alt keydown
    @ctrl = true  if _([16, 17, 18]).indexOf(e.which, true) > -1
    
    # Enter submits the command
    if e.which is 13
      e.preventDefault()
      val = @textarea.val()
      
      # If shift is down, do a carriage return
      if @ctrl
        @currentHistory = val + "\n"
        @update()
        return false
      
      # If submitting a command, set the currentHistory to blank (empties the textarea on update)
      @currentHistory = ""
      
      # Run the command past the special commands to check for ':help' and ':clear' etc.
      # If if wasn't a special command, pass off to the Sandbox Model to evaluate and save
      @model.evaluate val  unless @specialCommands(val)
      
      # Update the View's history state to reflect the latest history item
      @historyState = @model.get("history").length
      return false
    
    # Up / down keys cycle through past history or move up/down
    if not @ctrl and (e.which is 38 or e.which is 40)
      e.preventDefault()
      history = @model.get("history")
      
      # `direction` is -1 or +1 to go forward/backward through command history
      direction = e.which - 39
      @historyState += direction
      
      # Keep it within bounds
      if @historyState < 0
        @historyState = 0
      else @historyState = history.length  if @historyState >= history.length
      
      # Update the currentHistory value and update the View
      @currentHistory = (if history[@historyState] then history[@historyState].command else "")
      @update()
      return false
    
    # Tab adds a tab character (instead of jumping focus)
    if e.which is 9
      e.preventDefault()
      
      # Get the value, and the parts between which the tab character will be inserted
      value = @textarea.val()
      caret = @getCaret()
      parts = [value.slice(0, caret), value.slice(caret, value.length)]
      
      # Insert the tab character into the value and update the textarea
      @textarea.val parts[0] + @tabCharacter + parts[1]
      
      # Set the caret (cursor) position to just after the inserted tab character
      @setCaret caret + @tabCharacter.length
      false

  
  # The keyup handler, used to switch off shift/alt keys
  keyUp: (e) ->
    
    # Register shift, alt and control keyup
    @ctrl = false  if _([16, 17, 18]).indexOf(e.which, true) > -1

  
  # Checks for special commands. If any are found, performs their action and returns true
  specialCommands: (command) ->
    if command is ":clear"
      @model.destroy()
      return true
    if command is ":help"
      return @model.addHistory(
        command: ":help"
        result: @helpText
      )
    if command is ":coffee" 
      @model.evaluator = @model.coffee
      @placeholder = "# type some coffeescript and hit enter (:help for info)"
      @render()
      return @model.addHistory(
          command: ":coffee"
          result: "Input is now evaluated as CoffeeScript"
        )
    if command is ":js" 
      @model.evaluator = @model.js
      @placeholder = "// type some javascript and hit enter (:help for info)"
      @render()
      return @model.addHistory(
          command: ":js"
          result: "Input is now evaluated as JavaScript"
        )
    
    # `:load <script src>`
    if command.indexOf(":load") > -1
      return @model.addHistory
        command: command
        result: @model.load(command.substring(6))

    
    # If no special commands, return false so the command gets evaluated
    false