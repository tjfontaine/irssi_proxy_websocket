var Handler = function(ws, view) {
  this.ws = ws;
  this.view = view
}

Handler.prototype.trigger = function(msg) {
  this.ws.send(JSON.stringify(msg))
}

Handler.prototype.listwindows = function() {
  this.trigger({
    event: 'listwindows',
  })
}

Handler.prototype.windowlist = function(msg) {
  var self = this;
  for(var i = 0; i < msg.windows.length; i++) {
    var win = msg.windows[i]
    self.view.add_window(self.view.activity_name(win.window, win.data_level), win.window);
  }
}

Handler.prototype.getscrollback = function(win) {
  this.trigger({
    event: 'getscrollback',
    window: win,
    color: false,
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
  this.view.append_message(msg.window, msg.line);
  this.view.scroll_to_bottom(msg.window)
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
