var Handler = function(ws, view) {
  this.ws = ws;
  this.view = view
}

Handler.prototype.trigger = function(msg) {
  this.ws.send(JSON.stringify(msg))
}

Handler.prototype.authenticate = function(password) {
  this.trigger({
    event: 'authenticate',
    password: password,
  })
}

Handler.prototype.authenticated = function(msg) {
  this.configure()
  this.listwindows()
}

Handler.prototype.configure = function() {
  this.trigger({
    event: 'configure',
    color: true,
  })
}

Handler.prototype.listwindows = function() {
  this.trigger({
    event: 'listwindows',
  })
}

Handler.prototype.windowlist = function(msg) {
  var self = this;
  var active = 0;
  for(var i = 0; i < msg.windows.length; i++) {
    var win = msg.windows[i]

    if (win.active) {
      active = win.window
    }

    self.view.add_window(win.window, win.window, win.data_level, win.items);
  }
  self.view.activate_window(active)
}

Handler.prototype.getscrollback = function(win) {
  this.trigger({
    event: 'getscrollback',
    window: win,
    color: true,
    count: 100,
  })
}

Handler.prototype.scrollback = function(msg) {
  this.view.set_content(msg.window, msg.lines)
  this.view.scroll_to_bottom(msg.window)
}

Handler.prototype.activewindow = function(win) {
  this.trigger({
    event: 'activewindow',
    window: win,
  })
  this.view.set_window_activity(win, 0)
}

Handler.prototype.addline = function(msg) {
  if (msg.window == this.view.current_window) {
    this.view.append_message(msg.window, msg.line);
    this.view.scroll_to_bottom(msg.window)
  }
}

Handler.prototype.addwindow = function(msg) {
  this.view.add_window(msg.window, msg.window)
}

Handler.prototype.delwindow = function(msg) {
  this.view.del_window(msg.window)
}

Handler.prototype.unhandled = function(msg) {
  this.view.log('UNHANDLED: ' + JSON.stringify(msg));
}

Handler.prototype.sendcommand = function(win, msg) {
  if(win > 0) {
    this.trigger({
      event: 'sendcommand',
      window: win,
      msg: msg,
    })
  }
}

Handler.prototype.activity = function(msg) {
  this.view.set_window_activity(msg.window, msg.level)
}

Handler.prototype.hilight = function(msg) {
  this.view.set_notification(msg.window, msg.line)
}

Handler.prototype.renumber = function(msg) {
  this.view.renumber(msg.old, msg.cur)
}

Handler.prototype.activeitem = function(win, item) {
  if (win > 0) {
    this.trigger({
      event: 'activeitem',
      window: win,
      name: item,
    })
  }
}

Handler.prototype.listitems = function(win) {
  if (win > 0) {
    this.trigger({
      event: 'listitems',
      window: win,
    })
  }
}

Handler.prototype.itemlist = function(msg) {
  this.view.set_items(msg.window, msg.items)
}
