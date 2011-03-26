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
  $.each(msg.windows, function(widx, win){
    self.view.add_window(win.window, win.window);
  })
}

Handler.prototype.getscrollback = function(win) {
  this.trigger({
    event: 'getscrollback',
    window: win,
  })
}

Handler.prototype.scrollback = function(msg) {
  this.view.set_content(msg.window, msg.lines.join('<br/>'))
  this.view.scroll_to_bottom(msg.window)
}

Handler.prototype.activewindow = function(win) {
  this.trigger({
    event: 'activewindow',
    window: win,
  })
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
  this.view.log('UNHANDLED: ' + msg.event);
}

Handler.prototype.sendcommand = function(window, msg) {
  this.trigger({
    event: 'sendcommand',
    window: win,
    msg: msg,
  })
}