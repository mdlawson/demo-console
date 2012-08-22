(function() {
  var __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  window.demoCon = {};

  /*
  The Sandbox.Model
  
  Takes care of command evaluation, history and persistence via localStorage adapter
  */


  demoCon.History = (function(_super) {

    __extends(History, _super);

    function History() {
      return History.__super__.constructor.apply(this, arguments);
    }

    History.prototype.defaults = {
      history: []
    };

    History.prototype.initialize = function() {
      _.bindAll(this);
      this.evaluator = this.js;
      this.fetch();
      return this.bind("destroy", function(model) {
        return model.set({
          history: []
        });
      });
    };

    History.prototype.localStorage = new Backbone.LocalStorage("DemoConsole");

    History.prototype.parse = function(data) {
      if (!_.isArray(data) || data.length < 1 || !data[0]) {
        return data;
      }
      data[0].history = _.map(data[0].history, function(command) {
        command._hidden = true;
        if (command.result) {
          delete command.result;
        }
        if (command._class) {
          delete command._class;
        }
        return command;
      });
      return data[0];
    };

    History.prototype.stringify = function(o, simple, visited) {
      var circular, i, json, names, parts, sortci, type, vi;
      json = "";
      i = void 0;
      vi = void 0;
      type = "";
      parts = [];
      names = [];
      circular = false;
      visited = visited || [];
      sortci = function(a, b) {
        if (a.toLowerCase() < b.toLowerCase()) {
          return -1;
        } else {
          return 1;
        }
      };
      try {
        type = {}.toString.call(o);
      } catch (e) {
        type = "[object Object]";
      }
      vi = 0;
      while (vi < visited.length) {
        if (o === visited[vi]) {
          circular = true;
          break;
        }
        vi++;
      }
      if (circular) {
        json = "[circular]";
      } else if (type === "[object String]") {
        json = "\"" + o.replace(/"/g, "\\\"") + "\"";
      } else if (type === "[object Array]") {
        visited.push(o);
        json = "[";
        i = 0;
        while (i < o.length) {
          parts.push(this.stringify(o[i], simple, visited));
          i++;
        }
        json += parts.join(", ") + "]";
        json;

      } else if (type === "[object Object]") {
        visited.push(o);
        json = "{";
        for (i in o) {
          names.push(i);
        }
        names.sort(sortci);
        i = 0;
        while (i < names.length) {
          parts.push(this.stringify(names[i], undefined, visited) + ": " + this.stringify(o[names[i]], simple, visited));
          i++;
        }
        json += parts.join(", ") + "}";
      } else if (type === "[object Number]") {
        json = o + "";
      } else if (type === "[object Boolean]") {
        json = (o ? "true" : "false");
      } else if (type === "[object Function]") {
        json = o.toString();
      } else if (o === null) {
        json = "null";
      } else if (o === undefined) {
        json = "undefined";
      } else if (simple === undefined) {
        visited.push(o);
        json = type + "{\n";
        for (i in o) {
          names.push(i);
        }
        names.sort(sortci);
        i = 0;
        while (i < names.length) {
          try {
            parts.push(names[i] + ": " + this.stringify(o[names[i]], true, visited));
          } catch (e) {
            e.name === "NS_ERROR_NOT_IMPLEMENTED";
          }
          i++;
        }
        json += parts.join(",\n") + "\n}";
      } else {
        try {
          json = o + "";
        } catch (_error) {}
      }
      return json;
    };

    History.prototype.addHistory = function(item) {
      var history;
      history = this.get("history");
      if (_.isString(item.result)) {
        item.result = "\"" + item.result.toString().replace(/"/g, "\\\"") + "\"";
      }
      if (_.isFunction(item.result)) {
        item.result = item.result.toString().replace(/"/g, "\\\"");
      }
      if (_.isObject(item.result)) {
        item.result = this.stringify(item.result).replace(/"/g, "\\\"");
      }
      if (_.isUndefined(item.result)) {
        item.result = "undefined";
      }
      history.push(item);
      this.save({
        history: history
      });
      this.trigger('change', this, history);
      return this;
    };

    History.prototype.load = function(src) {
      var script;
      script = document.createElement("script");
      script.type = "text/javascript";
      script.src = src;
      return document.body.appendChild(script);
    };

    History.prototype.evaluate = function(command) {
      var item;
      if (!command) {
        return false;
      }
      item = {
        command: command
      };
      try {
        item.result = this.evaluator(command);
        if (_.isUndefined(item.result)) {
          item._class = "undefined";
        }
        if (_.isNumber(item.result)) {
          item._class = "number";
        }
        if (_.isString(item.result)) {
          item._class = "string";
        }
      } catch (error) {
        item.result = error.toString();
        item._class = "error";
      }
      return this.addHistory(item);
    };

    History.prototype.js = function(command) {
      return eval.call(window, command);
    };

    History.prototype.coffee = function(command) {
      return CoffeeScript["eval"].call(window, command);
    };

    return History;

  })(Backbone.Model);

  /*
  The Sandbox.View
  
  Defers to the Sandbox.Model for history, evaluation and persistence
  Takes care of all the rendering, controls, events and special commands
  */


  demoCon.View = (function(_super) {

    __extends(View, _super);

    function View() {
      return View.__super__.constructor.apply(this, arguments);
    }

    View.prototype.initialize = function(opts) {
      _.bindAll(this);
      this.model = new demoCon.History;
      this.historyState = this.model.get("history").length;
      this.currentHistory = "";
      this.resultPrefix = opts.resultPrefix || "  => ";
      this.tabCharacter = opts.tabCharacter || "\t";
      this.placeholder = opts.placeholder || "// type some javascript and hit enter (:help for info)";
      this.helpText = opts.helpText || "type javascript commands into the console, hit enter to evaluate. \n[up/down] to scroll through history, ':clear' to reset it. \n[alt + return/up/down] for returns and multi-line editing.\n':coffee' tells the console to evaluate input as coffeescript,\n':js' tells it you are using js again";
      this.model.bind("change", this.update);
      return this.render();
    };

    View.prototype.events = {
      "keydown textarea": "keyDown",
      "keyup textarea": "keyUp",
      "click .output": "focus"
    };

    View.prototype.template = _.template($("#tplSandbox").html());

    View.prototype.format = _.template($("#tplCommand").html());

    View.prototype.render = function() {
      var $el;
      $el = $(this.el);
      $el.html(this.template({
        placeholder: this.placeholder
      }));
      this.textarea = $el.find("textarea");
      this.output = $el.find(".output");
      return this;
    };

    View.prototype.update = function() {
      this.output.html(_.reduce(this.model.get("history"), function(memo, command) {
        return memo + this.format({
          _hidden: command._hidden,
          _class: command._class,
          command: this.toEscaped(command.command),
          result: this.toEscaped(command.result)
        });
      }, "", this));
      this.textarea.val(this.currentHistory).attr("rows", this.currentHistory.split("\n").length);
      return this.output.scrollTop(this.output[0].scrollHeight - this.output.height());
    };

    View.prototype.setValue = function(command) {
      this.currentHistory = command;
      this.update();
      this.setCaret(this.textarea.val().length);
      this.textarea.focus();
      return false;
    };

    View.prototype.getCaret = function() {
      if (this.textarea[0].selectionStart) {
        return this.textarea[0].selectionStart;
      }
      return 0;
    };

    View.prototype.setCaret = function(index) {
      this.textarea[0].selectionStart = index;
      return this.textarea[0].selectionEnd = index;
    };

    View.prototype.toEscaped = function(string) {
      return String(string).replace(/\\"/g, "\"").replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/'/g, "&#39;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    };

    View.prototype.focus = function(e) {
      e.preventDefault();
      this.textarea.focus();
      return false;
    };

    View.prototype.keyDown = function(e) {
      var caret, direction, history, parts, val, value;
      if (_([16, 17, 18]).indexOf(e.which, true) > -1) {
        this.ctrl = true;
      }
      if (e.which === 13) {
        e.preventDefault();
        val = this.textarea.val();
        if (this.ctrl) {
          this.currentHistory = val + "\n";
          this.update();
          return false;
        }
        this.currentHistory = "";
        if (!this.specialCommands(val)) {
          this.model.evaluate(val);
        }
        this.historyState = this.model.get("history").length;
        return false;
      }
      if (!this.ctrl && (e.which === 38 || e.which === 40)) {
        e.preventDefault();
        history = this.model.get("history");
        direction = e.which - 39;
        this.historyState += direction;
        if (this.historyState < 0) {
          this.historyState = 0;
        } else {
          if (this.historyState >= history.length) {
            this.historyState = history.length;
          }
        }
        this.currentHistory = (history[this.historyState] ? history[this.historyState].command : "");
        this.update();
        return false;
      }
      if (e.which === 9) {
        e.preventDefault();
        value = this.textarea.val();
        caret = this.getCaret();
        parts = [value.slice(0, caret), value.slice(caret, value.length)];
        this.textarea.val(parts[0] + this.tabCharacter + parts[1]);
        this.setCaret(caret + this.tabCharacter.length);
        return false;
      }
    };

    View.prototype.keyUp = function(e) {
      if (_([16, 17, 18]).indexOf(e.which, true) > -1) {
        return this.ctrl = false;
      }
    };

    View.prototype.specialCommands = function(command) {
      if (command === ":clear") {
        this.model.destroy();
        return true;
      }
      if (command === ":help") {
        return this.model.addHistory({
          command: ":help",
          result: this.helpText
        });
      }
      if (command === ":coffee") {
        this.model.evaluator = this.model.coffee;
        this.placeholder = "# type some coffeescript and hit enter (:help for info)";
        this.render();
        return this.model.addHistory({
          command: ":coffee",
          result: "Input is now evaluated as CoffeeScript"
        });
      }
      if (command === ":js") {
        this.model.evaluator = this.model.js;
        this.placeholder = "// type some javascript and hit enter (:help for info)";
        this.render();
        return this.model.addHistory({
          command: ":js",
          result: "Input is now evaluated as JavaScript"
        });
      }
      if (command.indexOf(":load") > -1) {
        return this.model.addHistory({
          command: command,
          result: this.model.load(command.substring(6))
        });
      }
      return false;
    };

    return View;

  })(Backbone.View);

}).call(this);
